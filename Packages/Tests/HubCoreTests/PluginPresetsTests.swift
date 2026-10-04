import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct PluginPresetsTests {
  let catalog = ModelCatalog(models: [], loras: [], fileCount: 0)
  let store = PresetStore(
    fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("PluginPresetsTests-\(UUID())/presets.json"))

  func plugin(_ name: String, steps: Int = 4, prompt: String = "") -> Preset {
    Preset(name: name, prompt: prompt, parameters: GenerationParameters(steps: steps), origin: "com.x")
  }

  @Test func newPresetsAreAddedAndKeepTheirOrigin() {
    let result = store.add(fromPlugin: [plugin("A"), plugin("B")])
    #expect(result.added == 2 && result.existing == 0)
    #expect(store.preset(named: "a")?.origin == "com.x")
  }

  @Test func aTakenNameIsNeverTouchedNotEvenByTheSamePlugin() {
    store.save(Preset(name: "A", parameters: GenerationParameters(steps: 30)))
    store.add(fromPlugin: [plugin("B", steps: 4)])
    store.save(Preset(name: "B", prompt: "edited", parameters: GenerationParameters(steps: 9), origin: "com.x"))
    let result = store.add(fromPlugin: [plugin("a", steps: 4), plugin("B", steps: 4)])
    #expect(result.added == 0 && result.existing == 2)
    #expect(store.preset(named: "A")?.parameters.steps == 30 && store.preset(named: "A")?.origin == nil)
    #expect(store.preset(named: "B")?.parameters.steps == 9 && store.preset(named: "B")?.prompt == "edited")
  }

  @Test func theUsersEditToAPluginsPresetKeepsItsOrigin() {
    store.add(fromPlugin: [plugin("B")])
    var edited = store.preset(named: "B")!
    edited.parameters.steps = 12
    store.save(edited)
    #expect(store.preset(named: "B")?.origin == "com.x" && store.preset(named: "B")?.parameters.steps == 12)
  }

  @Test func theMissingPresetsOfAPipelineAreNamedOnceInOrder() {
    store.add(fromPlugin: [plugin("A")])
    let pipeline = PluginPipeline(steps: [
      PipelineStep(preset: "B"), PipelineStep(preset: "A"), PipelineStep(preset: "C"), PipelineStep(), PipelineStep(preset: "B"),
    ])
    #expect(PipelinePresets.missing(in: pipeline, store: store) == ["B", "C"])
  }

  @Test func aPassRunsThePresetOnTheTabWithoutItsModelOrSize() {
    var preset = Preset(name: "Match", model: "other.ckpt", prompt: "match the light", parameters: GenerationParameters(width: 2048, height: 256, steps: 4))
    preset.parameters.loras = [LoRASelection(file: "sun.ckpt", weight: 0.6)]
    store.save(preset)
    var tab = GenerationFields(prompt: "tab prompt", negativePrompt: "tab negative")
    tab.parameters.width = 768
    tab.parameters.height = 1280
    tab.parameters.steps = 30
    let used = PipelinePresets.fields(for: PipelineStep(preset: "match"), over: tab, store: store, catalog: catalog)
    #expect(used.prompt == "match the light" && used.negativePrompt == "tab negative")
    #expect(used.parameters.steps == 4 && used.parameters.loras.map(\.file) == ["sun.ckpt"])
    #expect(used.parameters.width == 768 && used.parameters.height == 1280)
  }

  @Test func aPassWithoutAPresetRunsTheTabAsItIs() {
    let tab = GenerationFields(prompt: "tab prompt")
    #expect(PipelinePresets.fields(for: PipelineStep(), over: tab, store: store, catalog: catalog) == tab)
    #expect(PipelinePresets.fields(for: PipelineStep(preset: "gone"), over: tab, store: store, catalog: catalog) == tab)
  }
}

@MainActor
struct PluginPresetsRoutingTests {
  let root = PluginFixture.folder()
  let presets = PresetStore(
    fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("PluginPresetsRouting-\(UUID())/presets.json"))

  func started() throws -> (PluginRegistry, FakeLoader) {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let settings = PluginSettingsStore(fileURL: root.deletingLastPathComponent().appendingPathComponent("presets-\(root.lastPathComponent).json"))
    settings.save(["a"])
    let loader = FakeLoader()
    let registry = PluginRegistry(folder: PluginFolder(root: root), settings: settings, loader: loader, tempFolder: root)
    registry.presetStore = presets
    registry.start()
    return (registry, loader)
  }

  func send(_ json: String, _ loader: FakeLoader) async throws -> [String: Any] {
    let reply = await (try #require(loader.host)).receive(Data(json.utf8), from: "a")
    return try #require(try JSONSerialization.jsonObject(with: reply) as? [String: Any])
  }

  @Test func anActivePluginAddsItsPresetsAndTheAnswerCountsThem() async throws {
    let (_, loader) = try started()
    let message = #"{"type":"presets","presets":[{"name":"One","fields":{"steps":4,"prompt":"hi"}},{"name":"Two"}]}"#
    let first = try await send(message, loader)
    #expect(first["type"] as? String == "ok" && first["added"] as? Int == 2 && first["existing"] as? Int == 0)
    #expect(presets.preset(named: "One")?.prompt == "hi" && presets.preset(named: "One")?.origin == "a")
    let again = try await send(message, loader)
    #expect(again["added"] as? Int == 0 && again["existing"] as? Int == 2)
  }

  @Test func anInactivePluginOrABadMessageAddsNothing() async throws {
    let (registry, loader) = try started()
    #expect(try await send(#"{"type":"presets"}"#, loader)["type"] as? String == "error")
    registry.setActive("a", false)
    #expect(try await send(#"{"type":"presets","presets":[{"name":"One"}]}"#, loader)["type"] as? String == "error")
    #expect(presets.presets.isEmpty)
  }
}
