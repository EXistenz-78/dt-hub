import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
final class FakeLoadedPlugin: LoadedPlugin {
  let manifest: PluginManifest
  let viewController: AnyObject = NSObject()
  private(set) var sent: [Data] = []

  init(manifest: PluginManifest) { self.manifest = manifest }

  func send(_ message: Data) async -> Data? {
    sent.append(message)
    return PluginMessageType.bare(PluginMessageType.ok)
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
    #expect(registry.entries.map(\.state) == [.off] && registry.entries.map(\.name) == ["A"])
    let newer = try PluginFixture.bundle(in: PluginFixture.folder(), id: "a", name: "A", version: "1.1")
    #expect(try registry.offer(for: newer).replacing == "1.0")
    #expect(throws: PluginError.notNewer(installed: "1.0")) { try registry.offer(for: source) }
    #expect(throws: PluginError.unreadable) { try registry.offer(for: PluginFixture.folder()) }
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

  @Test func aNoticeFromAPluginIsShownWithItsName() throws {
    try PluginFixture.bundle(in: root, id: "a", name: "Alpha")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    let reply = try #require(loader.host).receive(Data(#"{"type":"notice","text":"Ready","isError":true}"#.utf8), from: "a")
    #expect(PluginMessageType.of(reply) == PluginMessageType.ok)
    #expect(registry.latestNotice?.pluginName == "Alpha" && registry.latestNotice?.text == "Ready")
    #expect(registry.latestNotice?.isError == true)
    registry.dismissNotice()
    #expect(registry.latestNotice == nil)
    let unknown = try #require(loader.host).receive(Data(#"{"type":"fly"}"#.utf8), from: "a")
    #expect(PluginMessageType.of(unknown) == PluginMessageType.unsupported)
  }
}
