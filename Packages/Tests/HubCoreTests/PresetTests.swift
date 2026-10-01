import Foundation
import HubKit
import Testing

@testable import HubCore

/// A codec that reads only `model` and `steps`, enough to test what the preset code does with it.
struct FakeCodec: ConfigurationCodec {
  func exportJSON(_ state: ConfigurationState) -> String { "{}" }
  func validate(_ json: String, for state: ConfigurationState) -> String? { nil }
  func unknownKeys(in json: String) -> [String] { [] }
  func apply(json: String, to state: ConfigurationState) throws(ConfigurationError) -> ConfigurationState {
    guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
      throw ConfigurationError("bad")
    }
    if object["broken"] != nil { throw ConfigurationError("broken") }
    var next = state
    if let model = object["model"] as? String { next.model = model }
    if let steps = object["steps"] as? Int { next.parameters.steps = steps }
    return next
  }
}

@MainActor
struct PresetStoreTests {
  func tempFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("PresetStoreTests-\(UUID())", isDirectory: true)
      .appendingPathComponent("presets.json")
  }

  @Test func startsEmptyWithoutAFile() {
    #expect(PresetStore(fileURL: tempFile()).presets.isEmpty)
  }

  @Test func remembersPresetsAcrossLaunchesByName() {
    let file = tempFile()
    let store = PresetStore(fileURL: file)
    store.save(Preset(name: "Zeta", model: "m.ckpt", negativePrompt: "blurry", parameters: GenerationParameters(steps: 20)))
    store.save(Preset(name: "alpha"))
    let again = PresetStore(fileURL: file)
    #expect(again.presets.map(\.name) == ["alpha", "Zeta"])
    #expect(again.preset(named: "zeta")?.parameters.steps == 20)
    #expect(again.preset(named: "ZETA")?.negativePrompt == "blurry")
  }

  @Test func savingUnderAnExistingNameReplacesIt() {
    let store = PresetStore(fileURL: tempFile())
    store.save(Preset(name: "Fast", parameters: GenerationParameters(steps: 4)))
    let id = store.presets[0].id
    store.save(Preset(name: "fast", parameters: GenerationParameters(steps: 8)))
    #expect(store.presets.count == 1)
    #expect(store.presets[0].id == id)
    #expect(store.presets[0].parameters.steps == 8)
  }

  @Test func anEmptyNameIsRefused() {
    let store = PresetStore(fileURL: tempFile())
    #expect(!store.save(Preset(name: "   ")))
    #expect(store.presets.isEmpty)
  }

  @Test func renamesAndDeletes() {
    let store = PresetStore(fileURL: tempFile())
    store.save(Preset(name: "A"))
    store.save(Preset(name: "B"))
    let a = store.preset(named: "A")!.id
    #expect(!store.rename(a, to: "b"))
    #expect(!store.rename(a, to: " "))
    #expect(store.rename(a, to: "C"))
    #expect(store.presets.map(\.name) == ["B", "C"])
    store.delete(a)
    #expect(store.presets.map(\.name) == ["B"])
  }

  @Test func importedPresetsNeverReplaceSavedOnes() {
    let store = PresetStore(fileURL: tempFile())
    store.save(Preset(name: "Qwen Image 2.1", parameters: GenerationParameters(steps: 99)))
    store.add(imported: [Preset(name: "Qwen Image 2.1"), Preset(name: "Qwen Image 2.1"), Preset(name: "Flux")])
    #expect(store.presets.map(\.name) == ["Flux", "Qwen Image 2.1", "Qwen Image 2.1 (2)", "Qwen Image 2.1 (3)"])
    #expect(store.preset(named: "Qwen Image 2.1")?.parameters.steps == 99)
  }

  @Test func aDamagedPresetDoesNotTakeTheOthers() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"[{"name": "Good", "parameters": {"steps": 5}}, {"model": "no name"}, 7]"#.utf8).write(to: file)
    let store = PresetStore(fileURL: file)
    #expect(store.presets.map(\.name) == ["Good"])
    #expect(store.presets[0].parameters.steps == 5)
  }

  @Test func anUnreadableFileMeansNoPresets() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: file)
    #expect(PresetStore(fileURL: file).presets.isEmpty)
  }
}

struct PresetImportTests {
  let list = """
    [{"name": "Qwen Image 2.1", "version": "qwen_image_2.1", "negative": "ugly",
      "configuration": {"model": "qwen_image_2.1_q8p.ckpt", "steps": 40}},
     {"name": "No configuration"},
     {"configuration": {"steps": 5}},
     {"name": "Broken", "configuration": {"broken": true}},
     {"name": "Flux", "configuration": {"steps": 8}},
     "not an object"]
    """

  @Test func readsTheValidEntriesAndCountsTheOthers() {
    let result = PresetImport.read(Data(list.utf8), codec: FakeCodec())
    #expect(result.presets.map(\.name) == ["Qwen Image 2.1", "Flux"])
    #expect(result.skipped == 4)
    #expect(result.presets[0].model == "qwen_image_2.1_q8p.ckpt")
    #expect(result.presets[0].negativePrompt == "ugly")
    #expect(result.presets[0].parameters.steps == 40)
    #expect(result.presets[1].model == "")
  }

  @Test func aFileThatIsNotAListGivesNothing() {
    let result = PresetImport.read(Data(#"{"name": "x"}"#.utf8), codec: FakeCodec())
    #expect(result.presets.isEmpty)
    #expect(result.skipped == 1)
    #expect(PresetImport.read(Data("garbage".utf8), codec: FakeCodec()).presets.isEmpty)
  }
}

struct PresetLoadTests {
  let catalog = ModelCatalog(
    models: [], loras: [CatalogLoRA(file: "a.ckpt", name: "A", family: "flux2_9b", trigger: "vintage tarot style")],
    fileCount: 1)

  @Test func fillsTheTriggerWordsFromTheCatalog() {
    let parameters = GenerationParameters(loras: [LoRASelection(file: "a.ckpt"), LoRASelection(file: "b.ckpt", trigger: "mine")])
    let filled = parameters.fillingTriggers(from: catalog)
    #expect(filled.loras.map(\.trigger) == ["vintage tarot style", "mine"])
  }

  @Test func loadingAPresetKeepsTheNegativePromptItDoesNotHave() {
    let withNegative = Preset(name: "a", model: "m.ckpt", negativePrompt: "blurry")
    let without = Preset(name: "b")
    #expect(PresetLoad.of(withNegative, currentNegativePrompt: "mine", catalog: catalog).negativePrompt == "blurry")
    #expect(PresetLoad.of(withNegative, currentNegativePrompt: "mine", catalog: catalog).model == "m.ckpt")
    #expect(PresetLoad.of(without, currentNegativePrompt: "mine", catalog: catalog).negativePrompt == "mine")
    #expect(PresetLoad.of(without, currentNegativePrompt: "mine", catalog: catalog).model == nil)
  }

  @Test func loadedParametersAreClamped() {
    let preset = Preset(name: "wild", parameters: GenerationParameters(steps: 9999))
    #expect(PresetLoad.of(preset, currentNegativePrompt: "", catalog: catalog).parameters.steps == 150)
  }
}
