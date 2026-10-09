import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct PipelineStepValuesTests {
  let catalog = ModelCatalog(models: [], loras: [], fileCount: 0)

  var tab: GenerationFields {
    var p = GenerationParameters(width: 832, height: 1216, steps: 8)
    p.advanced.clipSkip = 2
    p.extra = ["foo": .int(1)]
    p.loras = [LoRASelection(file: "x.ckpt", weight: 1)]
    return GenerationFields(prompt: "a cat", negativePrompt: "n", parameters: p)
  }

  func step(_ json: String, preset: String = "", loras: [LoRASelection] = []) -> PipelineStep {
    let value = try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    guard case .object(let object) = value else { fatalError() }
    return PipelineStep(preset: preset, fields: FieldOverlay(json: object), loras: loras)
  }

  func run(_ step: PipelineStep, presets: [String: Preset] = [:]) -> GenerationFields {
    PipelinePresets.fields(for: step, over: tab, presets: presets, catalog: catalog)
  }

  @Test func fieldsChangeOnlyTheirOwnValues() {
    let used = run(step(#"{"steps":20}"#))
    #expect(used.parameters.steps == 20)
    #expect(used.parameters.advanced.clipSkip == 2)
    #expect(used.parameters.extra["foo"] == .int(1))
    #expect(used.prompt == "a cat" && used.negativePrompt == "n")
    #expect(used.parameters.loras == tab.parameters.loras)
  }

  @Test func aSizeInFieldsIsIgnored() {
    let used = run(step(#"{"steps":20,"width":1024,"height":512}"#))
    #expect(used.parameters.width == 832 && used.parameters.height == 1216 && used.parameters.steps == 20)
  }

  @Test func fieldsWinOverThePreset() throws {
    let preset = Preset(name: "P", prompt: "from preset", parameters: GenerationParameters(steps: 4, guidanceScale: 3))
    let used = run(step(#"{"steps":30}"#, preset: "P"), presets: ["P": preset])
    #expect(used.parameters.steps == 30)
    #expect(used.parameters.guidanceScale == 3)
    #expect(used.prompt == "from preset")
  }

  @Test func lorasUpdateAnExistingOneInPlaceAndAddNewOnesAtTheEnd() {
    let used = run(
      step("{}", loras: [LoRASelection(file: "y.ckpt", weight: 1.0), LoRASelection(file: "x.ckpt", weight: 0.6)]))
    #expect(used.parameters.loras.map(\.file) == ["x.ckpt", "y.ckpt"])
    #expect(used.parameters.loras.map(\.weight) == [0.6, 1.0])
  }

  @Test func anExistingLoRAKeepsItsModeAndTriggerUnlessTheStepGivesOthers() {
    var base = tab
    base.parameters.loras = [LoRASelection(file: "x.ckpt", weight: 1, mode: .refiner, trigger: "zzz")]
    let plain = PipelinePresets.fields(
      for: PipelineStep(loras: [LoRASelection(file: "x.ckpt", weight: 0.4)]), over: base, presets: [:], catalog: catalog)
    #expect(plain.parameters.loras == [LoRASelection(file: "x.ckpt", weight: 0.4, mode: .refiner, trigger: "zzz")])
    let given = PipelinePresets.fields(
      for: PipelineStep(loras: [LoRASelection(file: "x.ckpt", weight: 0.4, mode: .base, trigger: "new")]), over: base,
      presets: [:], catalog: catalog)
    #expect(given.parameters.loras == [LoRASelection(file: "x.ckpt", weight: 0.4, mode: .base, trigger: "new")])
  }

  @Test func anEmptyStepRunsTheTabAsItIs() {
    #expect(run(PipelineStep()) == tab)
  }

  @Test func aPresetOnlyStepIsAsBefore() throws {
    let preset = Preset(name: "P", prompt: "pp", parameters: GenerationParameters(steps: 4))
    let step = PipelineStep(preset: "P")
    let used = PipelinePresets.fields(for: step, over: tab, presets: ["P": preset], catalog: catalog)
    let load = PresetLoad.of(preset, current: tab, catalog: catalog)
    #expect(used == GenerationFields(prompt: load.prompt, negativePrompt: load.negativePrompt, parameters: load.parameters))
  }
}
