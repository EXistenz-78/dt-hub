import Foundation
import HubKit
import Observation

/// One line of the plug-in list.
public struct PluginEntry: Identifiable, Equatable, Sendable {
  public enum State: Equatable, Sendable {
    /// Installed, turned off.
    case off
    /// Turned on but not loaded yet: it loads at the next launch.
    case loadsAtNextLaunch
    /// Turned on, but plug-ins were skipped at this launch (⌥ held).
    case skipped
    case loaded
    case failed(PluginError)
  }

  public let id: String
  public let url: URL
  public let name: String
  /// The version in the folder.
  public var version: String
  /// The version of the code that is running (nil unless loaded); it differs from `version` after an
  /// update that takes effect at the next launch.
  public var runningVersion: String?
  public var state: State
  /// Whether it counts for the work in hand (the header menu); only a loaded plug-in can be.
  public var isActive: Bool
  public var manifest: PluginManifest?
}

/// A line a plug-in asked the app to show.
public struct PluginNoticeItem: Identifiable, Equatable, Sendable {
  public let id = UUID()
  public let pluginID: String
  public let pluginName: String
  public let text: String
  public let isError: Bool
}

/// What the user is about to install.
public struct PluginInstallOffer: Equatable, Sendable {
  public let source: URL
  public let info: PluginBundleInfo
  /// The version that will be replaced, if the plug-in is installed already.
  public let replacing: String?
}

/// The plug-ins of the app: what is installed, turned on, loaded and active (plug-in design §4, §5).
@MainActor
@Observable
public final class PluginRegistry: PluginHosting {
  public private(set) var entries: [PluginEntry] = []
  /// The banner's line; closing the banner clears it, not the history.
  public private(set) var latestNotice: PluginNoticeItem?
  /// Every notice received, newest first, 20 at most.
  public private(set) var notices: [PluginNoticeItem] = []
  /// A change (a plug-in turned on or off, installed, replaced or removed while loaded) waits for a restart.
  public private(set) var needsRestart = false
  public private(set) var family: String?
  public private(set) var model: String?

  /// What the active plug-ins contributed (teal fields, conflicts, the pipeline); the app sets its `target`.
  public let contributions = ContributionStore()
  /// The Preset menu's store, where the presets a plug-in brings go; set by the app.
  @ObservationIgnored public var presetStore: PresetStore?
  /// Answers a plug-in's question to the language model (`llm` message); nil = no language model. `modelName` is the
  /// model of the models folder the plug-in asks for; nil = the one chosen in the settings.
  @ObservationIgnored public var askLanguageModel:
    (@MainActor (_ prompt: String, _ images: [URL], _ options: LanguageModelOptions, _ modelName: String?) async throws -> String)?
  /// The path of the Control tab's start image, when there is one; read whenever a context is sent.
  @ObservationIgnored public var startImagePath: (@MainActor () -> String?)?
  /// The paths of the Moodboard pictures that are on; read whenever a context is sent.
  @ObservationIgnored public var moodboardPaths: (@MainActor () -> [String])?
  /// The language models of the models folder; read whenever a context is sent.
  @ObservationIgnored public var languageModels: (@MainActor () -> [PluginLanguageModel])?

  @ObservationIgnored private let folder: PluginFolder
  @ObservationIgnored private let settings: PluginSettingsStore
  @ObservationIgnored private let loader: any PluginLoading
  @ObservationIgnored private let tempFolder: URL
  @ObservationIgnored private var loaded: [String: any LoadedPlugin] = [:]
  @ObservationIgnored private var skipPlugins = false
  @ObservationIgnored private var removedWhileLoaded = false

  public init(folder: PluginFolder, settings: PluginSettingsStore, loader: any PluginLoading, tempFolder: URL) {
    self.folder = folder
    self.settings = settings
    self.loader = loader
    self.tempFolder = tempFolder
  }

  /// Scans the folder and loads the plug-ins that are on (none when `skipping`, the ⌥ key at launch).
  public func start(skipping: Bool = false) {
    skipPlugins = skipping
    try? FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
    let enabled = settings.enabled()
    entries = folder.scan().map { slot in
      guard let info = slot.info else {
        return PluginEntry(
          id: Self.brokenID(slot.url), url: slot.url, name: slot.identifier, version: "",
          state: .failed(slot.error ?? .unreadable), isActive: false, manifest: nil)
      }
      var entry = PluginEntry(
        id: info.identifier, url: slot.url, name: info.name, version: info.version, state: .off, isActive: false,
        manifest: nil)
      guard enabled.contains(info.identifier) else { return entry }
      if skipping {
        entry.state = .skipped
        return entry
      }
      do {
        let plugin = try loader.load(slot.url, info: info, host: self)
        loaded[info.identifier] = plugin
        entry.state = .loaded
        entry.isActive = true
        entry.runningVersion = info.version
        entry.manifest = plugin.manifest
      } catch {
        entry.state = .failed((error as? PluginError) ?? .loadFailed(String(describing: error)))
      }
      return entry
    }
    for entry in entries where entry.isActive { send(PluginMessageType.bare(PluginMessageType.activate), to: entry.id) }
    updateRestartFlag()
  }

  /// The id of a row whose bundle could not be read: it cannot clash with a plug-in's identifier.
  nonisolated static func brokenID(_ url: URL) -> String { "broken:\(url.lastPathComponent)" }

  // MARK: Installing

  /// Reads the bundle the user chose and says what would happen; nothing is copied yet.
  public func offer(for source: URL) throws(PluginError) -> PluginInstallOffer {
    let info = try PluginBundleReader.read(source)
    let replacing = folder.installed(info.identifier)?.version
    if let replacing, !(PluginVersion(info.version) > PluginVersion(replacing)) {
      throw .notNewer(installed: replacing)
    }
    return PluginInstallOffer(source: source, info: info, replacing: replacing)
  }

  /// Copies the plug-in in (the user confirmed). A new plug-in is off; a replaced one keeps its switch
  /// and takes effect at the next launch.
  public func install(_ offer: PluginInstallOffer) throws(PluginError) {
    try folder.install(offer.source, info: offer.info)
    // A new plug-in is turned on by the install (the user just confirmed it); an update keeps the switch.
    if offer.replacing == nil {
      var enabled = settings.enabled()
      enabled.insert(offer.info.identifier)
      settings.save(enabled)
    }
    refreshEntries()
  }

  public func remove(_ identifier: String) throws(PluginError) {
    // A plug-in that is going away stops contributing now, not at the next launch.
    setActive(identifier, false)
    if entries.first(where: { $0.id == identifier })?.state == .loaded { removedWhileLoaded = true }
    if let row = entries.first(where: { $0.id == identifier }), identifier.hasPrefix("broken:") {
      try folder.remove(folderAt: row.url)
    } else {
      try folder.remove(identifier)
    }
    var enabled = settings.enabled()
    enabled.remove(identifier)
    settings.save(enabled)
    refreshEntries()
  }

  /// Turns a plug-in on or off. The code loads at the next launch (and stays loaded until then).
  public func setEnabled(_ identifier: String, _ isOn: Bool) {
    var enabled = settings.enabled()
    if isOn { enabled.insert(identifier) } else { enabled.remove(identifier) }
    settings.save(enabled)
    guard let index = entries.firstIndex(where: { $0.id == identifier }) else { return }
    if isOn {
      if entries[index].state == .off { entries[index].state = skipPlugins ? .skipped : .loadsAtNextLaunch }
    } else if entries[index].state != .loaded {
      entries[index].state = .off
    }
    // A plug-in already loaded stays loaded until the next launch, but it follows the switch for the job:
    // off takes its teal, its brackets and its pipeline and it stops contributing (plug-in design §7).
    if entries[index].state == .loaded { setActive(identifier, isOn) }
    updateRestartFlag()
  }

  /// Whether a plug-in is turned on in the settings.
  public func isEnabled(_ identifier: String) -> Bool { settings.enabled().contains(identifier) }

  /// Folder scan after an install or a removal, keeping what is loaded.
  private func refreshEntries() {
    let enabled = settings.enabled()
    let previous = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    entries = folder.scan().map { slot in
      guard let info = slot.info else {
        return PluginEntry(
          id: Self.brokenID(slot.url), url: slot.url, name: slot.identifier, version: "",
          state: .failed(slot.error ?? .unreadable), isActive: false, manifest: nil)
      }
      if let old = previous[info.identifier] {
        // What is loaded stays; a load that failed stays failed until the bundle changes.
        if old.state == .loaded {
          var kept = old
          kept.version = info.version
          return kept
        }
        if case .failed = old.state, old.url == slot.url, old.version == info.version { return old }
      }
      var entry = PluginEntry(
        id: info.identifier, url: slot.url, name: info.name, version: info.version, state: .off, isActive: false,
        manifest: nil)
      if enabled.contains(info.identifier) { entry.state = skipPlugins ? .skipped : .loadsAtNextLaunch }
      return entry
    }
    updateRestartFlag()
  }

  private func updateRestartFlag() {
    let enabled = settings.enabled()
    needsRestart =
      removedWhileLoaded
      || entries.contains { entry in
        switch entry.state {
        case .loadsAtNextLaunch: true
        case .loaded: !enabled.contains(entry.id) || entry.runningVersion != entry.version
        default: false
        }
      }
  }

  // MARK: Active plug-ins and tabs

  /// Puts a loaded plug-in in or out of the work in hand (the header menu).
  public func setActive(_ identifier: String, _ isActive: Bool) {
    guard let index = entries.firstIndex(where: { $0.id == identifier }), entries[index].state == .loaded,
      entries[index].isActive != isActive
    else { return }
    entries[index].isActive = isActive
    if !isActive { contributions.forget(identifier) }
    send(PluginMessageType.bare(isActive ? PluginMessageType.activate : PluginMessageType.deactivate), to: identifier)
    if isActive { sendContext(to: identifier) }
  }

  /// A plug-in works with the chosen model's family (the header menu greys it out otherwise).
  public func isCompatible(_ entry: PluginEntry) -> Bool { entry.manifest?.supports(family: family) ?? false }

  /// The tabs of the plug-ins that are loaded, active and compatible with the model's family.
  public var activeTabs: [WorkspaceTab] {
    entries.compactMap { entry in
      guard entry.state == .loaded, entry.isActive, isCompatible(entry), let manifest = entry.manifest else { return nil }
      return WorkspaceTab(id: "plugin.\(entry.id)", title: manifest.name, systemImage: manifest.symbol)
    }
  }

  /// The view controller of a plug-in's tab (an `NSViewController`).
  public func viewController(forTab tabID: String) -> AnyObject? {
    guard tabID.hasPrefix("plugin.") else { return nil }
    return loaded[String(tabID.dropFirst("plugin.".count))]?.viewController
  }

  // MARK: Messages

  /// The model or its parameters changed: active plug-ins hear about it.
  public func updateContext(model: String?, family: String?, parameters: GenerationParameters) {
    self.model = model
    self.family = family
    latestParameters = parameters
    for entry in entries where entry.state == .loaded && entry.isActive { sendContext(to: entry.id) }
  }

  @ObservationIgnored private var latestParameters = GenerationParameters()

  /// Tells the active plug-ins where the app stands again, for what changed without the model or its parameters
  /// changing (a model added to the models folder, a start image): the app calls it when a plug-in's tab is shown.
  public func refreshContext() {
    for entry in entries where entry.state == .loaded && entry.isActive { sendContext(to: entry.id) }
  }

  private func sendContext(to identifier: String) {
    let context = PluginContext(
      model: model, family: family, parameters: latestParameters, tempFolder: tempFolder.path,
      startImage: startImagePath?(), moodboard: moodboardPaths.flatMap { $0().nilIfEmpty },
      languageModels: languageModels?())
    guard let data = try? JSONEncoder().encode(context) else { return }
    send(data, to: identifier)
  }

  private func send(_ message: Data, to identifier: String) {
    guard let plugin = loaded[identifier] else { return }
    Task { _ = await plugin.send(message) }
  }

  public func dismissNotice() { latestNotice = nil }

  /// The newest notice a plug-in sent.
  public func lastNotice(of identifier: String) -> PluginNoticeItem? {
    notices.first { $0.pluginID == identifier }
  }

  // MARK: PluginHosting

  public func receive(_ message: Data, from pluginID: String) async -> Data {
    switch PluginMessageType.of(message) {
    case PluginMessageType.contribute:
      return contribute(message, from: pluginID)
    case PluginMessageType.presets:
      return addPresets(message, from: pluginID)
    case PluginMessageType.llm:
      return await askModel(message, from: pluginID)
    case PluginMessageType.notice:
      if let notice = try? JSONDecoder().decode(PluginNotice.self, from: message) {
        let name = entries.first { $0.id == pluginID }?.name ?? pluginID
        let item = PluginNoticeItem(pluginID: pluginID, pluginName: name, text: notice.text, isError: notice.isError)
        latestNotice = item
        notices.insert(item, at: 0)
        if notices.count > 20 { notices.removeLast(notices.count - 20) }
      }
      return PluginMessageType.bare(PluginMessageType.ok)
    default:
      return PluginMessageType.bare(PluginMessageType.unsupported)
    }
  }

  private func isActive(_ pluginID: String) -> Bool {
    entries.first { $0.id == pluginID }?.isActive ?? false
  }

  /// Only a plug-in that is on for this job contributes; the answer says how it went.
  private func contribute(_ message: Data, from pluginID: String) -> Data {
    guard isActive(pluginID) else { return PluginMessageType.failure("The plug-in is not active.") }
    guard let contribution = PluginContribution(message: message) else {
      return PluginMessageType.failure("The message is not a JSON object.")
    }
    let problems = contributions.receive(contribution, from: pluginID)
    var answer: [String: Any] = ["type": PluginMessageType.ok, "conflicts": contributions.conflicts.count]
    if !problems.isEmpty { answer["problems"] = problems }
    return (try? JSONSerialization.data(withJSONObject: answer)) ?? PluginMessageType.bare(PluginMessageType.ok)
  }

  /// Presets for the Preset menu; a name already there is left alone, a name the file system does not take is
  /// refused. `{"type":"ok","added":n,"existing":m,"rejected":k}`.
  private func addPresets(_ message: Data, from pluginID: String) -> Data {
    guard isActive(pluginID) else { return PluginMessageType.failure("The plug-in is not active.") }
    guard let store = presetStore else { return PluginMessageType.failure("There is no preset store.") }
    guard let parsed = PluginPresets(message: message) else {
      return PluginMessageType.failure("The message has no presets list.")
    }
    let result = store.add(fromPlugin: parsed.presets)
    let answer: [String: Any] = [
      "type": PluginMessageType.ok, "added": result.added, "existing": result.existing, "rejected": result.rejected,
    ]
    return (try? JSONSerialization.data(withJSONObject: answer)) ?? PluginMessageType.bare(PluginMessageType.ok)
  }

  /// `{"type":"llm","prompt":…,"images":[paths],"system":…,"model":name,"options":{…}}` → `{"type":"llm","text":…}`.
  private func askModel(_ message: Data, from pluginID: String) async -> Data {
    guard isActive(pluginID) else { return PluginMessageType.failure("The plug-in is not active.") }
    guard let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any],
      let prompt = object["prompt"] as? String, !prompt.isEmpty
    else { return PluginMessageType.failure("The message has no prompt.") }
    guard let ask = askLanguageModel else { return PluginMessageType.failure("There is no language model.") }
    let images = (object["images"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
    let options = LanguageModelOptions(message: object)
    let modelName = (object["model"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    do {
      let text = try await ask(prompt, images, options, modelName)
      return (try? JSONSerialization.data(withJSONObject: ["type": PluginMessageType.llm, "text": text]))
        ?? PluginMessageType.failure("The answer could not be sent.")
    } catch let error as LanguageModelError {
      return PluginMessageType.failure(error.plainText)
    } catch {
      return PluginMessageType.failure(String(describing: error))
    }
  }
}

private extension Array {
  /// nil for an empty list: a key with nothing to say is left out of the context.
  var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}
