import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct SeamlessWiringTests {
  let catalog = ModelCatalog(
    models: [CatalogModel(file: "krea_2.ckpt", name: "Krea 2", family: "krea_2")], loras: [], fileCount: 1)

  func batches(_ seamless: SeamlessTile?) -> [GenerationJob] {
    if let seamless {
      return JobComposer.batches(
        prompt: "p", negativePrompt: "", model: "krea_2.ckpt", family: "krea_2", parameters: GenerationParameters(),
        catalog: catalog, seamlessTile: seamless) { 1 }
    }
    return JobComposer.batches(
      prompt: "p", negativePrompt: "", model: "krea_2.ckpt", family: "krea_2", parameters: GenerationParameters(),
      catalog: catalog) { 1 }
  }

  @Test func theComposerPutsSeamlessOnEveryJobOfThePass() {
    var parameters = GenerationParameters()
    parameters.batchCount = 3
    let jobs = JobComposer.batches(
      prompt: "p", negativePrompt: "", model: "krea_2.ckpt", family: "krea_2", parameters: parameters, catalog: catalog,
      seamlessTile: .leftRight) { 1 }
    #expect(jobs.count == 3 && jobs.allSatisfy { $0.seamlessTile == .leftRight })
  }

  @Test func aNormalRunNeverCarriesIt() {
    #expect(batches(nil).allSatisfy { $0.seamlessTile == nil })
  }

  @Test func theContextSaysWhetherTheServerIsCustom() async throws {
    let root = PluginFixture.folder()
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let settingsFile = root.deletingLastPathComponent().appendingPathComponent("settings-\(root.lastPathComponent).json")
    let settings = PluginSettingsStore(fileURL: settingsFile)
    settings.save(["a"])
    let loader = FakeLoader()
    let registry = PluginRegistry(folder: PluginFolder(root: root), settings: settings, loader: loader, tempFolder: root)
    var custom = true
    registry.customServer = { custom }
    registry.start()
    registry.updateContext(model: "m.ckpt", family: "krea_2", parameters: GenerationParameters())
    try? await Task.sleep(for: .milliseconds(30))
    let plugin = try #require(loader.plugins["a"])
    func lastContext() throws -> [String: Any] {
      let data = try #require(plugin.sent.last { PluginMessageType.of($0) == PluginMessageType.context })
      return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    #expect(try lastContext()["customServer"] as? Bool == true)
    custom = false
    registry.refreshContext()
    try? await Task.sleep(for: .milliseconds(30))
    #expect(try lastContext()["customServer"] as? Bool == false)
  }

  @Test func theRegistryRefusesASeamlessPipelineWithoutTheCustomServer() async throws {
    let root = PluginFixture.folder()
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let settingsFile = root.deletingLastPathComponent().appendingPathComponent("settings-\(root.lastPathComponent).json")
    let settings = PluginSettingsStore(fileURL: settingsFile)
    settings.save(["a"])
    let loader = FakeLoader()
    let registry = PluginRegistry(folder: PluginFolder(root: root), settings: settings, loader: loader, tempFolder: root)
    let target = FakeContributionTarget()
    registry.contributions.target = target
    registry.customServer = { false }
    registry.start()
    registry.updateContext(model: "m.ckpt", family: "krea_2", parameters: GenerationParameters())
    try? await Task.sleep(for: .milliseconds(30))
    let host = try #require(loader.host)
    let message = Data(#"{"type":"contribute","pipeline":{"steps":[{"seamless":"both"}]}}"#.utf8)
    let reply = await host.receive(message, from: "a")
    let object = try #require(JSONSerialization.jsonObject(with: reply) as? [String: Any])
    #expect(object["problems"] as? [String] == ["seamless: the custom server is not running."])
    #expect(registry.contributions.pipeline == nil)
    registry.customServer = { true }
    _ = await host.receive(message, from: "a")
    #expect(registry.contributions.pipeline?.pluginID == "a")
    withExtendedLifetime(target) {}
  }
}
