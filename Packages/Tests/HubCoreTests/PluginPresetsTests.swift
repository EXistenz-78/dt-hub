import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct PluginPresetsTests {
  let catalog = ModelCatalog(models: [], loras: [], fileCount: 0)
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PluginPresetsTests-\(UUID())", isDirectory: true)
  var store: PresetStore { PresetStore(folder: folder) }

  func plugin(_ name: String, steps: Int = 4, prompt: String = "") -> Preset {
    Preset(name: name, prompt: prompt, parameters: GenerationParameters(steps: steps))
  }

  @Test func newPresetsAreAddedAsFiles() {
    let result = store.add(fromPlugin: [plugin("SMP · A"), plugin("SMP · B")])
    #expect(result.added == 2 && result.existing == 0 && result.rejected == 0)
    #expect(store.names == ["SMP · A", "SMP · B"])
  }

  @Test func aTakenNameIsNeverTouchedAndABadNameIsRefused() throws {
    let store = self.store
    try store.save(Preset(name: "SMP · A", parameters: GenerationParameters(steps: 30)))
    try store.save(Preset(name: "SMP · B", prompt: "edited", parameters: GenerationParameters(steps: 9)))
    let result = store.add(fromPlugin: [plugin("smp · a", steps: 4), plugin("SMP · B", steps: 4), plugin("SMP/C"), plugin("SMP: D"), plugin("SMP · E")])
    #expect(result.added == 1 && result.existing == 2 && result.rejected == 2)
    #expect(store.preset(named: "SMP · A")?.parameters.steps == 30)
    #expect(store.preset(named: "SMP · B")?.parameters.steps == 9 && store.preset(named: "SMP · B")?.prompt == "edited")
    #expect(store.names == ["SMP · A", "SMP · B", "SMP · E"])
  }

  @Test func thePipelineReadsOnlyThePresetsItNamesOnceEach() throws {
    let store = self.store
    try store.save(plugin("A"))
    try store.save(plugin("B"))
    try store.save(plugin("Unused"))
    let pipeline = PluginPipeline(steps: [PipelineStep(preset: "A"), PipelineStep(), PipelineStep(preset: "a"), PipelineStep(preset: "B")])
    guard case .success(let loaded) = PipelinePresets.load(pipeline, from: store) else { Issue.record("expected success"); return }
    #expect(Set(loaded.keys) == ["A", "a", "B"])
    #expect(loaded["a"]?.name == "A")
  }

  @Test func aPipelineWithMissingOrUnreadablePresetsFailsNamingThemOnceInOrder() throws {
    let store = self.store
    try store.save(plugin("A"))
    try Data("garbage".utf8).write(to: folder.appendingPathComponent("Bad.json"))
    let pipeline = PluginPipeline(steps: [
      PipelineStep(preset: "B"), PipelineStep(preset: "A"), PipelineStep(preset: "C"), PipelineStep(preset: "Bad"),
      PipelineStep(), PipelineStep(preset: "B"),
    ])
    guard case .failure(let problem) = PipelinePresets.load(pipeline, from: store) else { Issue.record("expected failure"); return }
    #expect(problem.missing == ["B", "C"] && problem.unreadable == ["Bad"])
  }

  @Test func aPassRunsThePresetOnTheTabWithoutItsModelOrSize() throws {
    var preset = Preset(name: "Match", model: "other.ckpt", prompt: "match the light", parameters: GenerationParameters(width: 2048, height: 256, steps: 4))
    preset.parameters.loras = [LoRASelection(file: "sun.ckpt", weight: 0.6)]
    let store = self.store
    try store.save(preset)
    var tab = GenerationFields(prompt: "tab prompt", negativePrompt: "tab negative")
    tab.parameters.width = 768
    tab.parameters.height = 1280
    tab.parameters.steps = 30
    let used = PipelinePresets.fields(for: PipelineStep(preset: "Match"), over: tab, presets: ["Match": try store.load(named: "match")], catalog: catalog)
    #expect(used.prompt == "match the light" && used.negativePrompt == "tab negative")
    #expect(used.parameters.steps == 4 && used.parameters.loras.map(\.file) == ["sun.ckpt"])
    #expect(used.parameters.width == 768 && used.parameters.height == 1280)
  }

  @Test func aPassWithoutAPresetRunsTheTabAsItIs() {
    let tab = GenerationFields(prompt: "tab prompt")
    #expect(PipelinePresets.fields(for: PipelineStep(), over: tab, presets: [:], catalog: catalog) == tab)
    #expect(PipelinePresets.fields(for: PipelineStep(preset: "gone"), over: tab, presets: [:], catalog: catalog) == tab)
  }
}

@MainActor
struct PluginPresetsRoutingTests {
  let root = PluginFixture.folder()
  let presets = PresetStore(
    folder: FileManager.default.temporaryDirectory.appendingPathComponent("PluginPresetsRouting-\(UUID())", isDirectory: true))

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
    #expect(presets.preset(named: "One")?.prompt == "hi" && presets.names == ["One", "Two"])
    let again = try await send(message, loader)
    #expect(again["added"] as? Int == 0 && again["existing"] as? Int == 2 && again["rejected"] as? Int == 0)
    let bad = try await send(#"{"type":"presets","presets":[{"name":"A/B"}]}"#, loader)
    #expect(bad["rejected"] as? Int == 1)
  }

  @Test func anInactivePluginOrABadMessageAddsNothing() async throws {
    let (registry, loader) = try started()
    #expect(try await send(#"{"type":"presets"}"#, loader)["type"] as? String == "error")
    registry.setActive("a", false)
    #expect(try await send(#"{"type":"presets","presets":[{"name":"One"}]}"#, loader)["type"] as? String == "error")
    #expect(presets.names.isEmpty)
  }
}
