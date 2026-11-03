import Foundation
import HubKit
import Observation

/// What the last check or install has to say, for the window and the preferences.
public enum UpdateMessage: Equatable, Sendable {
  case upToDate
  case unreachable
  /// GitHub answered, but this release has no manifest this app can read.
  case noInformation
  /// The outcome of each item of the last install.
  case results([UpdateResult])
}

public struct UpdateResult: Equatable, Sendable {
  public let id: String
  public let name: String
  public let error: UpdateError?
}

/// Drives the automatic update: the check at launch, the offers, and (after the user's confirmation) the install.
@MainActor
@Observable
public final class UpdateController {
  public enum State: Equatable, Sendable {
    case idle
    case checking
    /// The name of the item being fetched and how far it is, 0…1.
    case installing(String, Double)
    /// An install ended; `message` has the results.
    case finished
  }

  public private(set) var state: State = .idle
  public private(set) var offers: [UpdateOffer] = []
  public private(set) var tag: String?
  public private(set) var message: UpdateMessage?
  /// The app was replaced: it is the new one at the next launch.
  public private(set) var needsRelaunch = false
  /// The app could not be swapped in place: the new one waits here to be dragged into the Applications folder.
  public private(set) var revealedApp: URL?
  public private(set) var lastCheck: Date?
  public private(set) var dismissed: [String: String]

  public var checkOnLaunchEnabled: Bool {
    didSet { settings.checkOnLaunch = checkOnLaunchEnabled }
  }

  /// What the banner shows: the offers the user has not put off.
  public var visibleOffers: [UpdateOffer] { UpdatePlan.visible(offers, dismissed: dismissed) }
  public let appVersion: String

  @ObservationIgnored private var settings: UpdateSettings
  @ObservationIgnored private let checker: UpdateChecker
  @ObservationIgnored private let installer: UpdateInstaller
  @ObservationIgnored private let replacer: AppReplacer
  @ObservationIgnored private let appURL: URL
  @ObservationIgnored private let appIdentifier: String
  @ObservationIgnored private let installedPlugins: @MainActor () -> [String: String]
  @ObservationIgnored private let installPlugin: @MainActor (URL) throws -> Void
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let workFolder: URL
  @ObservationIgnored private let downloads: URL
  @ObservationIgnored private let base: URL
  @ObservationIgnored private var manifest: ReleaseManifest?

  public init(
    checker: UpdateChecker, installer: UpdateInstaller, replacer: AppReplacer, settings: UpdateSettings,
    appVersion: String, appURL: URL, appIdentifier: String,
    installedPlugins: @escaping @MainActor () -> [String: String],
    installPlugin: @escaping @MainActor (URL) throws -> Void, now: @escaping @Sendable () -> Date = Date.init,
    workFolder: URL, downloads: URL, base: URL = UpdateEndpoint.base
  ) {
    self.checker = checker
    self.installer = installer
    self.replacer = replacer
    self.settings = settings
    self.appVersion = appVersion
    self.appURL = appURL
    self.appIdentifier = appIdentifier
    self.installedPlugins = installedPlugins
    self.installPlugin = installPlugin
    self.now = now
    self.workFolder = workFolder
    self.downloads = downloads
    self.base = base
    checkOnLaunchEnabled = settings.checkOnLaunch
    lastCheck = settings.lastCheck
    dismissed = settings.dismissed
  }

  // MARK: Checking

  /// The check at launch: only when it is switched on and the last one is old enough; a failure says nothing.
  public func checkOnLaunch() async {
    guard settings.isDue(now: now()) else { return }
    await check(silent: true)
  }

  /// «Controlla ora»: always, and the outcome is told.
  public func checkNow() async {
    await check(silent: false)
  }

  private func check(silent: Bool) async {
    // One thing at a time: a second check, or one during an install, leaves the first as it is.
    guard state == .idle || state == .finished else { return }
    state = .checking
    let result = await checker.check(base: base)
    state = .idle
    switch result {
    case .manifest(let manifest):
      self.manifest = manifest
      tag = manifest.tag
      remember()
      // The app replaced in this run is the new one at the next launch: it is not offered again.
      offers = UpdatePlan.make(
        manifest: manifest, appVersion: appVersion, installedPlugins: installedPlugins(),
        supportedContracts: PluginContract.supported
      ).filter { !($0.isApp && needsRelaunch) }
      message = silent || !offers.isEmpty ? nil : .upToDate
    case .noInformation:
      manifest = nil
      remember()
      offers = []
      message = silent ? nil : .noInformation
    case .unreachable:
      message = silent ? nil : .unreachable
    }
  }

  private func remember() {
    let date = now()
    settings.markChecked(at: date)
    lastCheck = date
  }

  // MARK: Installing

  /// «Più tardi»: the offers now shown stay hidden until a higher version comes.
  public func putOff() {
    settings.dismiss(visibleOffers)
    dismissed = settings.dismissed
  }

  /// Leaves the results behind (the window closed).
  public func clearResults() {
    guard state == .finished else { return }
    state = .idle
    message = nil
  }

  /// Fetches and installs the chosen items — the plug-ins first, then the app. An item that fails does not stop the
  /// others; every outcome is in `message`.
  public func install(_ selected: Set<String>) async {
    guard state == .idle || state == .finished, let manifest else { return }
    let chosen = offers.filter { selected.contains($0.id) }
    guard !chosen.isEmpty else { return }
    let ordered = chosen.filter { !$0.isApp } + chosen.filter(\.isApp)
    needsRelaunch = false
    revealedApp = nil
    message = nil
    var results: [UpdateResult] = []
    for offer in ordered {
      state = .installing(offer.item.name, 0)
      let error = await installOne(offer, manifest: manifest)
      results.append(UpdateResult(id: offer.id, name: offer.item.name, error: error))
    }
    try? FileManager.default.removeItem(at: workFolder)
    let done = Set(results.filter { $0.error == nil }.map(\.id))
    offers.removeAll { done.contains($0.id) }
    message = .results(results)
    state = .finished
  }

  private func installOne(_ offer: UpdateOffer, manifest: ReleaseManifest) async -> UpdateError? {
    let name = offer.item.name
    let bundle: URL
    do {
      bundle = try await installer.fetchBundle(
        offer.item, manifest: manifest, base: base, work: workFolder,
        progress: { [weak self] fraction in
          Task { @MainActor in
            // A late report must not bring back a state the install has left.
            guard let self, case .installing(let current, _) = self.state, current == name else { return }
            self.state = .installing(name, fraction)
          }
        })
    } catch {
      return error
    }
    if offer.isApp {
      do {
        let outcome = try await replacer.replace(
          running: appURL, runningIdentifier: appIdentifier, runningVersion: appVersion, with: bundle,
          work: workFolder, downloads: downloads)
        switch outcome {
        case .replaced: needsRelaunch = true
        case .revealed(let url): revealedApp = url
        }
        return nil
      } catch {
        return error
      }
    }
    do {
      try installPlugin(bundle)
      return nil
    } catch let error as PluginError {
      return .plugin(error)
    } catch {
      return .cannotWrite(error.localizedDescription)
    }
  }
}
