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
  func tempFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("PresetStoreTests-\(UUID())", isDirectory: true)
  }

  func files(_ folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
  }

  @Test func startsEmptyWithoutAFolder() {
    #expect(PresetStore(folder: tempFolder()).names.isEmpty)
  }

  @Test func eachPresetIsAFileNamedAfterItAndTheNameIsNotInTheJSON() throws {
    let folder = tempFolder()
    let store = PresetStore(folder: folder)
    try store.save(Preset(name: "Zeta", model: "m.ckpt", negativePrompt: "blurry", parameters: GenerationParameters(steps: 20)))
    try store.save(Preset(name: "alpha"))
    #expect(files(folder) == ["Zeta.json", "alpha.json"])
    #expect(store.names == ["alpha", "Zeta"])
    #expect(!(try String(contentsOf: folder.appendingPathComponent("Zeta.json"), encoding: .utf8)).contains("\"name\""))
    let again = PresetStore(folder: folder)
    #expect(again.preset(named: "zeta")?.parameters.steps == 20)
    #expect(again.preset(named: "ZETA")?.negativePrompt == "blurry")
    #expect(again.preset(named: "zeta")?.name == "Zeta")
  }

  @Test func savingUnderAnExistingNameReplacesTheFileEvenIfOnlyTheCapitalsDiffer() throws {
    let folder = tempFolder()
    let store = PresetStore(folder: folder)
    try store.save(Preset(name: "Fast", parameters: GenerationParameters(steps: 4)))
    try store.save(Preset(name: "fast", parameters: GenerationParameters(steps: 8)))
    #expect(files(folder) == ["Fast.json"] && store.names == ["Fast"])
    #expect(store.preset(named: "Fast")?.parameters.steps == 8)
  }

  @Test func namesTheFileSystemDoesNotTakeAreRefused() {
    let folder = tempFolder()
    let store = PresetStore(folder: folder)
    for bad in ["   ", "a/b", "a:b", ".hidden"] {
      #expect(throws: PresetError.invalidName) { try store.save(Preset(name: bad)) }
    }
    #expect(store.names.isEmpty && files(folder).isEmpty)
    #expect(PresetStore.isValidName("SMP · Overcast") && !PresetStore.isValidName("a:b"))
  }

  @Test func theSizeIsNotKeptInTheFile() throws {
    let store = PresetStore(folder: tempFolder())
    try store.save(Preset(name: "P", parameters: GenerationParameters(width: 512, height: 1536)))
    #expect(store.preset(named: "P")?.parameters.width == GenerationParameters.default.width)
    #expect(store.preset(named: "P")?.parameters.height == GenerationParameters.default.height)
  }

  @Test func renamesAndDeletesTheFile() throws {
    let folder = tempFolder()
    let store = PresetStore(folder: folder)
    try store.save(Preset(name: "A"))
    try store.save(Preset(name: "B"))
    #expect(throws: PresetError.nameTaken) { try store.rename("A", to: "b") }
    #expect(throws: PresetError.invalidName) { try store.rename("A", to: " ") }
    #expect(throws: PresetError.notFound("Z")) { try store.rename("Z", to: "Y") }
    try store.rename("A", to: "C")
    #expect(store.names == ["B", "C"] && files(folder) == ["B.json", "C.json"])
    try store.rename("C", to: "c")
    #expect(store.names == ["B", "c"])
    store.delete(named: "B")
    #expect(store.names == ["c"] && files(folder) == ["c.json"])
  }

  @Test func importedPresetsNeverReplaceSavedOnesAndTheirNamesBecomeValid() throws {
    let store = PresetStore(folder: tempFolder())
    try store.save(Preset(name: "Qwen Image 2.1", parameters: GenerationParameters(steps: 99)))
    store.add(imported: [Preset(name: "Qwen Image 2.1"), Preset(name: "Qwen Image 2.1"), Preset(name: "Flux 1/2: fast")])
    #expect(store.names == ["Flux 1-2- fast", "Qwen Image 2.1", "Qwen Image 2.1 (2)", "Qwen Image 2.1 (3)"])
    #expect(store.preset(named: "Qwen Image 2.1")?.parameters.steps == 99)
  }

  @Test func aDamagedFileIsListedFailsWhenLoadedAndDoesNotTakeTheOthers() throws {
    let folder = tempFolder()
    let store = PresetStore(folder: folder)
    try store.save(Preset(name: "Good", parameters: GenerationParameters(steps: 5)))
    try Data("garbage".utf8).write(to: folder.appendingPathComponent("Bad.json"))
    store.refresh()
    #expect(store.names == ["Bad", "Good"])
    #expect(throws: PresetError.unreadable("Bad")) { try store.load(named: "bad") }
    #expect(store.preset(named: "Bad") == nil)
    #expect(store.preset(named: "Good")?.parameters.steps == 5)
  }

  @Test func aFileAddedOrEditedByHandIsSeenWithoutARestart() throws {
    let folder = tempFolder()
    let store = PresetStore(folder: folder)
    try store.save(Preset(name: "A", parameters: GenerationParameters(steps: 4)))
    try Data(#"{"parameters":{"steps":7},"prompt":"by hand"}"#.utf8).write(to: folder.appendingPathComponent("Hand.json"))
    var edited = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("A.json"))) as! [String: Any]
    edited["prompt"] = "edited"
    try JSONSerialization.data(withJSONObject: edited).write(to: folder.appendingPathComponent("A.json"))
    #expect(store.preset(named: "Hand")?.parameters.steps == 7 && store.preset(named: "Hand")?.prompt == "by hand")
    #expect(store.preset(named: "A")?.prompt == "edited")
    #expect(store.names == ["A", "Hand"])
  }

  @Test func filesThatAreNotJSONOrAreHiddenAreNotPresets() throws {
    let folder = tempFolder()
    let store = PresetStore(folder: folder)
    try store.save(Preset(name: "A"))
    try Data("x".utf8).write(to: folder.appendingPathComponent("notes.txt"))
    try Data("{}".utf8).write(to: folder.appendingPathComponent(".hidden.json"))
    store.refresh()
    #expect(store.names == ["A"])
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
    #expect(PresetLoad.of(withNegative, current: GenerationFields(negativePrompt: "mine"), catalog: catalog).negativePrompt == "blurry")
    #expect(PresetLoad.of(withNegative, current: GenerationFields(negativePrompt: "mine"), catalog: catalog).model == "m.ckpt")
    #expect(PresetLoad.of(without, current: GenerationFields(negativePrompt: "mine"), catalog: catalog).negativePrompt == "mine")
    #expect(PresetLoad.of(without, current: GenerationFields(negativePrompt: "mine"), catalog: catalog).model == nil)
  }

  @Test func loadedParametersAreClamped() {
    let preset = Preset(name: "wild", parameters: GenerationParameters(steps: 9999))
    #expect(PresetLoad.of(preset, current: GenerationFields(), catalog: catalog).parameters.steps == 150)
  }
}
