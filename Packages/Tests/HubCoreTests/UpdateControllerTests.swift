import Foundation
import Testing

@testable import HubCore

@MainActor
struct UpdateControllerTests {
  typealias Box = AppReplacerTests.Box

  nonisolated static let sha = String(repeating: "ab", count: 32)

  /// A manifest file with the app 1.0.0 and plug-ins A and B at the given versions.
  static func manifest(app: String = "1.0.0", a: String = "2", b: String = "2") -> Data {
    func plugin(_ id: String, _ version: String) -> String {
      """
      {"id": "\(id)", "name": "Plug \(id)", "version": "\(version)", "contract": 1,
       "asset": "\(id.uppercased()).dthubplugin.zip", "sha256": "\(sha)", "size": 100}
      """
    }
    return Data(
      """
      {"schema": 1, "tag": "v\(app)",
       "app": {"version": "\(app)", "asset": "DT-Hub.zip", "sha256": "\(sha)", "size": 1000},
       "plugins": [\(plugin("a", a)), \(plugin("b", b))]}
      """.utf8)
  }

  /// Everything the controller needs, with the world faked.
  @MainActor struct Rig {
    let scene = try! AppReplacerTests.Scene()
    let answer = Box(UpdateFetch.ok(UpdateControllerTests.manifest()))
    let fetches = Box(0)
    let installedPlugins = Box(["a": "1", "b": "1"])
    let installed = Box<[String]>([])
    let badAssets = Box<Set<String>>([])
    let delay: UInt64
    let defaults: UserDefaults
    let controller: UpdateController

    init(delay: UInt64 = 0, slowDownload: Bool = false, reportsProgress: Bool = false, lastCheck: Date? = nil) {
      self.delay = delay
      let defaults = UpdateSettingsTests.defaults()
      if let lastCheck { defaults.set(lastCheck, forKey: UpdateSettings.lastCheckKey) }
      self.defaults = defaults
      let answer = self.answer, fetches = self.fetches, bad = self.badAssets, installed = self.installed
      let plugins = self.installedPlugins
      let scene = self.scene
      let checker = UpdateChecker(fetch: { _ in
        fetches.value += 1
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return answer.value
      })
      let installer = UpdateInstaller(
        download: { _, destination, progress in
          // A report that arrives after the install is over.
          if reportsProgress { Task.detached { try? await Task.sleep(nanoseconds: 30_000_000); progress(0.5) } }
          if slowDownload { try await Task.sleep(nanoseconds: 50_000_000) }
          try Data().write(to: destination)
        },
        unzip: { zip, folder in
          let asset = zip.lastPathComponent
          if asset == "DT-Hub.zip" {
            try AppReplacerTests.Scene.makeApp(
              folder.appendingPathComponent("DT Hub.app"), identifier: AppReplacerTests.identifier, version: "1.0.0")
          } else {
            let id = String(asset.prefix(1)).lowercased()
            try UpdateInstallerTests.makeBundle(
              in: folder, name: asset.replacingOccurrences(of: ".zip", with: ""), identifier: id, version: "2")
          }
        },
        sha256: { url in bad.value.contains(url.lastPathComponent) ? "00" : UpdateControllerTests.sha })
      let replacer = AppReplacer(verifySignature: { _ in true }, trash: { _ in })
      controller = UpdateController(
        checker: checker, installer: installer, replacer: replacer, settings: UpdateSettings(defaults: defaults),
        appVersion: "0.9.0", appURL: scene.running, appIdentifier: AppReplacerTests.identifier,
        installedPlugins: { plugins.value }, installPlugin: { installed.value.append($0.lastPathComponent) },
        now: { UpdateSettingsTests.start }, workFolder: scene.root.appendingPathComponent("update-work"),
        downloads: scene.downloads, base: ReleaseManifestTests.base)
    }
  }

  @Test func theLaunchCheckSkipsTheNetworkWhenOffOrNotDue() async {
    let off = Rig()
    off.controller.checkOnLaunchEnabled = false
    await off.controller.checkOnLaunch()
    #expect(off.fetches.value == 0)

    let recent = Rig(lastCheck: UpdateSettingsTests.start.addingTimeInterval(-3600))
    await recent.controller.checkOnLaunch()
    #expect(recent.fetches.value == 0)

    let due = Rig(lastCheck: UpdateSettingsTests.start.addingTimeInterval(-13 * 3600))
    await due.controller.checkOnLaunch()
    #expect(due.fetches.value == 1)
  }

  @Test func theLaunchCheckFailsInSilenceButCheckNowSaysSo() async {
    let rig = Rig()
    rig.answer.value = .failed
    await rig.controller.checkOnLaunch()
    #expect(rig.fetches.value == 1)
    #expect(rig.controller.message == nil && rig.controller.lastCheck == nil)
    await rig.controller.checkNow()
    #expect(rig.controller.message == .unreachable)
  }

  @Test func aNewerReleaseProducesOffersAndRemembersTheCheck() async {
    let rig = Rig()
    await rig.controller.checkOnLaunch()
    #expect(rig.controller.offers.map(\.id) == ["app", "a", "b"])
    #expect(rig.controller.tag == "v1.0.0")
    #expect(rig.controller.lastCheck == UpdateSettingsTests.start)
    #expect(rig.controller.state == .idle)
  }

  @Test func putOffHidesTheOffersUntilAHigherVersion() async {
    let rig = Rig()
    await rig.controller.checkNow()
    rig.controller.putOff()
    #expect(rig.controller.visibleOffers.isEmpty)
    rig.answer.value = .ok(Self.manifest(app: "1.1.0", a: "2", b: "3"))
    await rig.controller.checkNow()
    #expect(rig.controller.visibleOffers.map(\.id) == ["app", "b"])
  }

  @Test func twoChecksAtOnceMakeOneRequest() async {
    let rig = Rig(delay: 50_000_000)
    async let first: Void = rig.controller.checkNow()
    async let second: Void = rig.controller.checkNow()
    _ = await (first, second)
    #expect(rig.fetches.value == 1)
  }

  @Test func installingDoesThePluginsThenTheApp() async {
    let rig = Rig()
    await rig.controller.checkNow()
    await rig.controller.install(["app", "a", "b"])
    #expect(rig.installed.value == ["A.dthubplugin", "B.dthubplugin"])
    #expect(rig.scene.version(of: rig.scene.running) == "1.0.0")
    #expect(rig.controller.needsRelaunch)
    #expect(rig.controller.state == .finished)
    guard case .results(let results) = rig.controller.message else {
      Issue.record("expected results")
      return
    }
    #expect(results.map(\.id) == ["a", "b", "app"] && results.allSatisfy { $0.error == nil })
    #expect(rig.controller.offers.isEmpty)
  }

  @Test func oneFailingItemDoesNotStopTheOthers() async {
    let rig = Rig()
    rig.badAssets.value = ["A.dthubplugin.zip"]
    await rig.controller.checkNow()
    await rig.controller.install(["app", "a", "b"])
    guard case .results(let results) = rig.controller.message else {
      Issue.record("expected results")
      return
    }
    #expect(results.first { $0.id == "a" }?.error == .checksum)
    #expect(results.first { $0.id == "b" }?.error == nil)
    #expect(results.first { $0.id == "app" }?.error == nil)
    #expect(rig.installed.value == ["B.dthubplugin"])
    // What failed is still on offer.
    #expect(rig.controller.offers.map(\.id) == ["a"])
  }

  @Test func onlyTheSelectedItemsAreInstalled() async {
    let rig = Rig()
    await rig.controller.checkNow()
    await rig.controller.install(["b"])
    #expect(rig.installed.value == ["B.dthubplugin"])
    #expect(rig.scene.version(of: rig.scene.running) == "0.9.0")
    #expect(!rig.controller.needsRelaunch)
    #expect(rig.controller.offers.map(\.id) == ["app", "a"])
  }

  @Test func aCheckWhileInstallingChangesNothing() async {
    let rig = Rig(slowDownload: true)
    await rig.controller.checkNow()
    let before = rig.controller.offers
    async let installing: Void = rig.controller.install(["a"])
    await Task.yield()
    rig.answer.value = .ok(Self.manifest(app: "9.0.0"))
    await rig.controller.checkNow()
    await installing
    #expect(rig.controller.offers.map(\.id) == before.map(\.id).filter { $0 != "a" })
    #expect(rig.controller.offers.first?.item.version == "1.0.0")
  }

  @Test func aRevealedAppIsReportedNotRelaunched() async throws {
    let rig = Rig()
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: rig.scene.apps.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rig.scene.apps.path) }
    await rig.controller.checkNow()
    await rig.controller.install(["app"])
    #expect(rig.controller.revealedApp?.lastPathComponent == "DT Hub.app")
    #expect(!rig.controller.needsRelaunch)
  }

  @Test func anAppAlreadyReplacedIsNotOfferedAgain() async {
    let rig = Rig()
    await rig.controller.checkNow()
    await rig.controller.install(["app"])
    #expect(rig.controller.needsRelaunch)
    await rig.controller.checkNow()
    #expect(!rig.controller.offers.contains { $0.isApp })
    #expect(rig.controller.needsRelaunch)
  }

  @Test func aLateProgressReportDoesNotBringBackTheInstallingState() async {
    let rig = Rig(reportsProgress: true)
    await rig.controller.checkNow()
    await rig.controller.install(["a"])
    try? await Task.sleep(nanoseconds: 100_000_000)
    #expect(rig.controller.state == .finished)
  }
}
