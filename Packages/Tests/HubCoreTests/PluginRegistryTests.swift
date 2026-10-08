import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
final class FakeLoadedPlugin: LoadedPlugin {
  let manifest: PluginManifest
  let viewController: AnyObject = NSObject()
  private(set) var sent: [Data] = []
  /// What the plug-in answers (a plug-in that does not know a message answers `unsupported`).
  var answer = PluginMessageType.bare(PluginMessageType.ok)

  init(manifest: PluginManifest) { self.manifest = manifest }

  func send(_ message: Data) async -> Data? {
    sent.append(message)
    return answer
  }

  var sentTypes: [String] { sent.compactMap { PluginMessageType.of($0) } }
}

@MainActor
final class FakeLoader: PluginLoading {
  var failures: [String: PluginError] = [:]
  var families: [String: [String]] = [:]
  private(set) var loadedIDs: [String] = []
  private(set) var plugins: [String: FakeLoadedPlugin] = [:]
  private(set) var host: (any PluginHosting)?

  func load(_ bundle: URL, info: PluginBundleInfo, host: any PluginHosting) throws(PluginError) -> any LoadedPlugin {
    if let error = failures[info.identifier] { throw error }
    self.host = host
    loadedIDs.append(info.identifier)
    let plugin = FakeLoadedPlugin(
      manifest: PluginManifest(
        id: info.identifier, name: info.name, version: info.version, symbol: "star", families: families[info.identifier]))
    plugins[info.identifier] = plugin
    return plugin
  }
}

@MainActor
struct PluginRegistryTests {
  let root = PluginFixture.folder()
  var settingsFile: URL { root.deletingLastPathComponent().appendingPathComponent("settings-\(root.lastPathComponent).json") }

  func registry(loader: FakeLoader = FakeLoader(), enabled: Set<String> = []) -> PluginRegistry {
    let settings = PluginSettingsStore(fileURL: settingsFile)
    settings.save(enabled)
    return PluginRegistry(folder: PluginFolder(root: root), settings: settings, loader: loader, tempFolder: root)
  }

  func settle() async { try? await Task.sleep(for: .milliseconds(30)) }

  @Test func onlyThePluginsThatAreOnAreLoaded() throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    try PluginFixture.bundle(in: root, id: "b", name: "B")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["b"])
    registry.start()
    #expect(loader.loadedIDs == ["b"])
    #expect(registry.entries.map(\.state) == [.off, .loaded])
    #expect(registry.entries.map(\.isActive) == [false, true])
    #expect(registry.activeTabs.map(\.title) == ["B"])
  }

  @Test func aPluginThatFailsToLoadIsReportedAndTheOthersLoad() throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    try PluginFixture.bundle(in: root, id: "b", name: "B")
    try PluginFixture.bundle(in: root, id: "c", name: "C", contract: 9)
    let loader = FakeLoader()
    loader.failures["a"] = .noEntryPoint
    let registry = registry(loader: loader, enabled: ["a", "b"])
    registry.start()
    #expect(registry.entries.map(\.state) == [.failed(.noEntryPoint), .loaded, .failed(.contractNotSupported(9))])
    #expect(registry.activeTabs.map(\.title) == ["B"])
  }

  @Test func skippingLoadsNothing() throws {
    try PluginFixture.bundle(in: root, id: "a")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start(skipping: true)
    #expect(loader.loadedIDs.isEmpty)
    #expect(registry.entries.map(\.state) == [.skipped])
    #expect(registry.activeTabs.isEmpty)
  }

  @Test func turningOneOnOrOffIsSavedAndTakesEffectAtTheNextLaunch() throws {
    try PluginFixture.bundle(in: root, id: "a")
    try PluginFixture.bundle(in: root, id: "b")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["b"])
    registry.start()
    registry.setEnabled("a", true)
    #expect(registry.entries.first { $0.id == "a" }?.state == .loadsAtNextLaunch)
    #expect(registry.isEnabled("a") && loader.loadedIDs == ["b"], "nothing loads before the next launch")
    registry.setEnabled("a", false)
    #expect(registry.entries.first { $0.id == "a" }?.state == .off)
    registry.setEnabled("b", false)
    #expect(registry.entries.first { $0.id == "b" }?.state == .loaded, "a loaded one stays until the next launch")
    #expect(PluginSettingsStore(fileURL: settingsFile).enabled().isEmpty)
    let again = PluginRegistry(
      folder: PluginFolder(root: root), settings: PluginSettingsStore(fileURL: settingsFile), loader: FakeLoader(),
      tempFolder: root)
    again.start()
    #expect(again.entries.allSatisfy { $0.state == .off })
  }

  @Test func theHeaderSwitchPutsALoadedPluginInOrOutOfTheWork() async throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    registry.updateContext(model: "m.ckpt", family: "flux2_9b", parameters: GenerationParameters(width: 512))
    await settle()
    let plugin = try #require(loader.plugins["a"])
    #expect(plugin.sentTypes.contains(PluginMessageType.activate) && plugin.sentTypes.contains(PluginMessageType.context))
    registry.setActive("a", false)
    #expect(registry.activeTabs.isEmpty)
    await settle()
    #expect(plugin.sentTypes.last == PluginMessageType.deactivate)
    registry.setActive("a", true)
    await settle()
    #expect(registry.activeTabs.map(\.id) == ["plugin.a"])
    #expect(Array(plugin.sentTypes.suffix(2)) == [PluginMessageType.activate, PluginMessageType.context])
  }

  @Test func theContextTellsAboutTheStartImageTheMoodboardAndTheLanguageModels() async throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    var startImage: String? = "/tmp/start.png"
    var models = [PluginLanguageModel(name: "a/pe", path: "/m/a/pe", supportsImages: true)]
    var moodboard = ["/tmp/m1.png", "/tmp/m2.png"]
    registry.startImagePath = { startImage }
    registry.moodboardPaths = { moodboard }
    registry.languageModels = { models }
    registry.start()
    registry.updateContext(model: "m.ckpt", family: "qwen_image_2.1", parameters: GenerationParameters())
    await settle()
    let plugin = try #require(loader.plugins["a"])
    func lastContext() throws -> PluginContext {
      let data = try #require(plugin.sent.last { PluginMessageType.of($0) == PluginMessageType.context })
      return try JSONDecoder().decode(PluginContext.self, from: data)
    }
    #expect(try lastContext().startImage == "/tmp/start.png")
    #expect(try lastContext().moodboard == ["/tmp/m1.png", "/tmp/m2.png"])
    #expect(try lastContext().languageModels == models)
    // The start image goes and a model arrives: nothing is sent until the app says so, then it is.
    startImage = nil
    moodboard = []
    models.append(PluginLanguageModel(name: "b", path: "/m/b", supportsImages: false))
    #expect(try lastContext().startImage == "/tmp/start.png")
    registry.refreshContext()
    await settle()
    #expect(try lastContext().startImage == nil)
    #expect(try lastContext().moodboard == nil)  // an empty Moodboard is left out, not sent as []
    #expect(try lastContext().languageModels?.count == 2)
  }

  @Test func refreshingTheContextTellsOnlyThePluginsThatAreOn() async throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    registry.setActive("a", false)
    await settle()
    let before = try #require(loader.plugins["a"]).sent.count
    registry.refreshContext()
    await settle()
    #expect(try #require(loader.plugins["a"]).sent.count == before)
  }

  @Test func aPluginForOtherFamiliesHasNoTabWhileAnotherModelIsChosen() throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let loader = FakeLoader()
    loader.families["a"] = ["qwen21"]
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    registry.updateContext(model: "q.ckpt", family: "qwen21", parameters: GenerationParameters())
    #expect(registry.activeTabs.map(\.title) == ["A"])
    registry.updateContext(model: "f.ckpt", family: "flux2_9b", parameters: GenerationParameters())
    #expect(registry.activeTabs.isEmpty)
    #expect(registry.entries.first.map(registry.isCompatible) == false)
    registry.updateContext(model: nil, family: nil, parameters: GenerationParameters())
    #expect(registry.activeTabs.map(\.title) == ["A"], "an unknown family: everything applies")
  }

  @Test func theTabsViewControllerIsTheLoadedPluginsOne() throws {
    try PluginFixture.bundle(in: root, id: "a")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    #expect(registry.viewController(forTab: "plugin.a") === loader.plugins["a"]?.viewController)
    #expect(registry.viewController(forTab: "plugin.zzz") == nil && registry.viewController(forTab: "generation") == nil)
  }

  @Test func installingOffersWhatWouldHappenAndCopiesAfterTheUserConfirms() throws {
    let registry = registry()
    registry.start()
    let source = try PluginFixture.bundle(in: PluginFixture.folder(), id: "a", name: "A", version: "1.0")
    let offer = try registry.offer(for: source)
    #expect(offer.info.name == "A" && offer.replacing == nil)
    #expect(registry.entries.isEmpty, "nothing is copied before the user confirms")
    try registry.install(offer)
    #expect(registry.entries.map(\.state) == [.loadsAtNextLaunch] && registry.entries.map(\.name) == ["A"])
    let newer = try PluginFixture.bundle(in: PluginFixture.folder(), id: "a", name: "A", version: "1.1")
    #expect(try registry.offer(for: newer).replacing == "1.0")
    #expect(throws: PluginError.notNewer(installed: "1.0")) { try registry.offer(for: source) }
    #expect(throws: PluginError.unreadable) { try registry.offer(for: PluginFixture.folder()) }
  }

  @Test func aLoadFailureStaysListedAfterAnUnrelatedInstall() throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let loader = FakeLoader()
    loader.failures["a"] = .noEntryPoint
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    #expect(registry.entries.map(\.state) == [.failed(.noEntryPoint)])
    let other = try PluginFixture.bundle(in: PluginFixture.folder(), id: "b", name: "B")
    try registry.install(registry.offer(for: other))
    #expect(registry.entries.first { $0.id == "a" }?.state == .failed(.noEntryPoint))
    #expect(registry.entries.first { $0.id == "b" }?.state == .loadsAtNextLaunch, "a new plug-in is turned on by the install")
  }

  @Test func twoFoldersOfOnePluginAreTwoRowsWithDifferentIdsAndNothingCrashes() throws {
    try PluginFixture.bundle(in: root, id: "com.x.p", version: "1.0", folderName: "Sample.dthubplugin")
    try PluginFixture.bundle(in: root, id: "com.x.p", version: "1.0", folderName: "com.x.p.dthubplugin")
    let registry = registry()
    registry.start()
    #expect(registry.entries.count == 2 && Set(registry.entries.map(\.id)).count == 2)
    let newer = try PluginFixture.bundle(in: PluginFixture.folder(), id: "com.x.p", version: "1.1")
    try registry.install(registry.offer(for: newer))
    #expect(registry.entries.count == 1 && registry.entries.first?.version == "1.1")
  }

  @Test func aBrokenRowCanBeRemovedWhateverItsFolderIsCalled() throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A", contract: 9, folderName: "weird.dthubplugin")
    let registry = registry()
    registry.start()
    let row = try #require(registry.entries.first)
    try registry.remove(row.id)
    #expect(registry.entries.isEmpty)
    #expect(PluginFolder(root: root).scan().isEmpty)
  }

  @Test func startMakesTheTemporaryFolderThePluginsAreTold() throws {
    let temp = root.appendingPathComponent("tmp-for-plugins", isDirectory: true)
    let registry = PluginRegistry(
      folder: PluginFolder(root: root), settings: PluginSettingsStore(fileURL: settingsFile), loader: FakeLoader(),
      tempFolder: temp)
    registry.start()
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: temp.path, isDirectory: &isDirectory) && isDirectory.boolValue)
  }

  @Test func aNewPluginIsTurnedOnByTheInstallButAnUpdateKeepsTheSwitchAsItWas() throws {
    let registry = registry()
    registry.start()
    let one = try PluginFixture.bundle(in: PluginFixture.folder(), id: "a", name: "A", version: "1.0")
    try registry.install(registry.offer(for: one))
    #expect(registry.isEnabled("a"))
    registry.setEnabled("a", false)
    let two = try PluginFixture.bundle(in: PluginFixture.folder(), id: "a", name: "A", version: "1.1")
    try registry.install(registry.offer(for: two))
    #expect(!registry.isEnabled("a"), "the user turned it off: an update does not turn it on again")
    #expect(registry.entries.map(\.state) == [.off])
  }

  @Test func theRowShowsTheInstalledVersionWhileTheRunningOneIsTheOldOne() throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A", version: "1.0")
    let registry = registry(enabled: ["a"])
    registry.start()
    #expect(registry.entries.first?.runningVersion == "1.0")
    let newer = try PluginFixture.bundle(in: PluginFixture.folder(), id: "a", name: "A", version: "2.0")
    try registry.install(registry.offer(for: newer))
    let row = try #require(registry.entries.first)
    #expect(row.state == .loaded && row.version == "2.0" && row.runningVersion == "1.0")
  }

  @Test func theRegistryKnowsWhenARestartIsNeeded() throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    try PluginFixture.bundle(in: root, id: "b", name: "B")
    let registry = registry(enabled: ["b"])
    registry.start()
    #expect(!registry.needsRestart)
    registry.setEnabled("a", true)
    #expect(registry.needsRestart, "a plug-in turned on loads at the next launch")
    registry.setEnabled("a", false)
    #expect(!registry.needsRestart)
    registry.setEnabled("b", false)
    #expect(registry.needsRestart, "a loaded plug-in turned off goes at the next launch")
    registry.setEnabled("b", true)
    #expect(!registry.needsRestart)
    try registry.remove("b")
    #expect(registry.needsRestart, "a loaded plug-in removed is still running until then")
  }

  @Test func theNoticesOfAPluginAreKeptNewestFirstEvenAfterTheBannerIsClosed() async throws {
    try PluginFixture.bundle(in: root, id: "a", name: "Alpha")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    let host = try #require(loader.host)
    _ = await host.receive(Data(#"{"type":"notice","text":"one"}"#.utf8), from: "a")
    _ = await host.receive(Data(#"{"type":"notice","text":"two"}"#.utf8), from: "a")
    #expect(registry.lastNotice(of: "a")?.text == "two")
    registry.dismissNotice()
    #expect(registry.latestNotice == nil && registry.lastNotice(of: "a")?.text == "two")
    #expect(registry.lastNotice(of: "zzz") == nil)
    for index in 0..<30 { _ = await host.receive(Data(#"{"type":"notice","text":"n\#(index)"}"#.utf8), from: "a") }
    #expect(registry.notices.count == 20 && registry.notices.first?.text == "n29")
  }

  @Test func removingForgetsThePluginAndItsSwitch() throws {
    try PluginFixture.bundle(in: root, id: "a")
    let registry = registry(enabled: ["a"])
    registry.start()
    try registry.remove("a")
    #expect(registry.entries.isEmpty)
    #expect(!registry.isEnabled("a"))
  }

  @Test func replacingALoadedPluginKeepsItLoadedUntilTheNextLaunch() throws {
    try PluginFixture.bundle(in: root, id: "a", version: "1.0")
    let registry = registry(enabled: ["a"])
    registry.start()
    let newer = try PluginFixture.bundle(in: PluginFixture.folder(), id: "a", version: "2.0")
    try registry.install(registry.offer(for: newer))
    #expect(registry.entries.map(\.state) == [.loaded])
    #expect(registry.entries.first?.isActive == true)
  }

  @Test func aNoticeFromAPluginIsShownWithItsName() async throws {
    try PluginFixture.bundle(in: root, id: "a", name: "Alpha")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    let reply = await (try #require(loader.host)).receive(Data(#"{"type":"notice","text":"Ready","isError":true}"#.utf8), from: "a")
    #expect(PluginMessageType.of(reply) == PluginMessageType.ok)
    #expect(registry.latestNotice?.pluginName == "Alpha" && registry.latestNotice?.text == "Ready")
    #expect(registry.latestNotice?.isError == true)
    registry.dismissNotice()
    #expect(registry.latestNotice == nil)
    let unknown = await (try #require(loader.host)).receive(Data(#"{"type":"fly"}"#.utf8), from: "a")
    #expect(PluginMessageType.of(unknown) == PluginMessageType.unsupported)
  }
}
