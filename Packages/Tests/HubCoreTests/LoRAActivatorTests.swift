import Foundation
import HubKit
import Testing

@testable import HubCore

/// Adding, removing and replacing LoRAs from the catalog, with the Turbo values applied and restored.
struct LoRAActivatorTests {
  private let catalog = ModelCatalog(
    models: [],
    loras: [
      CatalogLoRA(file: "t.ckpt", name: "T", family: nil, category: "turbo", steps: 4, guidance: 1, shift: 3),
      CatalogLoRA(file: "t2.ckpt", name: "T2", family: nil, category: "turbo", steps: 6, guidance: 2, shift: 5),
      CatalogLoRA(file: "s.ckpt", name: "S", family: nil, category: "style", steps: 9, guidance: 9, shift: 9),
      CatalogLoRA(file: "ts.ckpt", name: "TS", family: nil, category: "turbo", steps: 8),
      CatalogLoRA(file: "tn.ckpt", name: "TN", family: nil, category: "turbo"),
    ], fileCount: 5)

  private func start() -> GenerationParameters {
    var parameters = GenerationParameters()
    parameters.steps = 20
    parameters.guidanceScale = 4
    parameters.shift = 2
    return parameters
  }

  @Test func addingATurboAppliesItsValues() {
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "t.ckpt", weight: 0.8), to: &parameters, catalog: catalog)
    #expect(parameters.loras.map(\.file) == ["t.ckpt"])
    #expect(parameters.steps == 4)
    #expect(parameters.guidanceScale == 1)
    #expect(parameters.shift == 3)
    #expect(activator.turbo.files == ["t.ckpt"])
  }

  @Test func addingANonTurboChangesNoParameter() {
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "s.ckpt"), to: &parameters, catalog: catalog)
    #expect(parameters.loras.map(\.file) == ["s.ckpt"])
    #expect(parameters.steps == 20)
    #expect(parameters.guidanceScale == 4)
    #expect(parameters.shift == 2)
    #expect(activator.turbo.files.isEmpty)
  }

  @Test func addingATurboWithNoValuesChangesNothing() {
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "tn.ckpt"), to: &parameters, catalog: catalog)
    #expect(parameters.loras.map(\.file) == ["tn.ckpt"])
    #expect(parameters.steps == 20)
    #expect(activator.turbo.files.isEmpty)
  }

  @Test func aTurboWithOnlyStepsChangesOnlyTheSteps() {
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "ts.ckpt"), to: &parameters, catalog: catalog)
    #expect(parameters.steps == 8)
    #expect(parameters.guidanceScale == 4)
    #expect(parameters.shift == 2)
  }

  @Test func removingRestoresTheValuesBefore() {
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "t.ckpt"), to: &parameters, catalog: catalog)
    activator.remove("t.ckpt", from: &parameters)
    #expect(parameters.loras.isEmpty)
    #expect(parameters.steps == 20)
    #expect(parameters.guidanceScale == 4)
    #expect(parameters.shift == 2)
    #expect(activator.turbo.files.isEmpty)
  }

  @Test func aValueChangedByHandSurvivesTheRemoval() {
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "t.ckpt"), to: &parameters, catalog: catalog)
    parameters.steps = 6
    activator.remove("t.ckpt", from: &parameters)
    #expect(parameters.steps == 6)
    #expect(parameters.guidanceScale == 4)
    #expect(parameters.shift == 2)
  }

  @Test func updatingTheWeightOfAnActiveTurboIsNotAnActivation() {
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "t.ckpt", weight: 0.5), to: &parameters, catalog: catalog)
    activator.add(LoRASelection(file: "t.ckpt", weight: 0.9), to: &parameters, catalog: catalog)
    #expect(parameters.loras.count == 1)
    #expect(parameters.loras[0].weight == 0.9)
    #expect(activator.turbo.files == ["t.ckpt"])
    activator.remove("t.ckpt", from: &parameters)
    #expect(parameters.steps == 20)
  }

  @Test func replaceTurboWithTurbo() {
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "t.ckpt"), to: &parameters, catalog: catalog)
    activator.replace("t.ckpt", with: LoRASelection(file: "t2.ckpt", weight: 0.7), in: &parameters, catalog: catalog)
    #expect(parameters.loras.map(\.file) == ["t2.ckpt"])
    #expect(parameters.loras[0].weight == 0.7)
    #expect(parameters.steps == 6)
    #expect(parameters.guidanceScale == 2)
    #expect(parameters.shift == 5)
    #expect(activator.turbo.files == ["t2.ckpt"])
    activator.remove("t2.ckpt", from: &parameters)
    #expect(parameters.steps == 20)
    #expect(parameters.guidanceScale == 4)
    #expect(parameters.shift == 2)
  }

  @Test func replaceNonTurboWithTurboAndViceVersa() {
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "s.ckpt"), to: &parameters, catalog: catalog)
    activator.replace("s.ckpt", with: LoRASelection(file: "t.ckpt"), in: &parameters, catalog: catalog)
    #expect(parameters.loras.map(\.file) == ["t.ckpt"])
    #expect(parameters.steps == 4)
    activator.replace("t.ckpt", with: LoRASelection(file: "s.ckpt"), in: &parameters, catalog: catalog)
    #expect(parameters.loras.map(\.file) == ["s.ckpt"])
    #expect(parameters.steps == 20)
    #expect(parameters.guidanceScale == 4)
    #expect(parameters.shift == 2)
    #expect(activator.turbo.files.isEmpty)
  }

  @Test func replaceDoesNothingWhenOldIsMissingOrNewIsAlreadyChosen() {
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "t.ckpt"), to: &parameters, catalog: catalog)
    activator.add(LoRASelection(file: "s.ckpt"), to: &parameters, catalog: catalog)
    let before = parameters
    activator.replace("missing", with: LoRASelection(file: "t2.ckpt"), in: &parameters, catalog: catalog)
    activator.replace("t.ckpt", with: LoRASelection(file: "s.ckpt"), in: &parameters, catalog: catalog)
    activator.replace("t.ckpt", with: LoRASelection(file: "t.ckpt"), in: &parameters, catalog: catalog)
    #expect(parameters == before)
    #expect(activator.turbo.files == ["t.ckpt"])
  }

  @Test func anUnknownFileOrAnEmptyCatalogJustAddsTheLoRA() {
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "unknown.ckpt"), to: &parameters, catalog: catalog)
    let empty = ModelCatalog(models: [], loras: [], fileCount: 0)
    activator.add(LoRASelection(file: "t.ckpt"), to: &parameters, catalog: empty)
    #expect(parameters.loras.map(\.file) == ["unknown.ckpt", "t.ckpt"])
    #expect(parameters.steps == 20)
    #expect(activator.turbo.files.isEmpty)
  }

  @Test func aPresetThatBringsATurboLoRAIsNeverOverwritten() {
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "t.ckpt"), to: &parameters, catalog: catalog)
    var preset = start()
    preset.steps = 30
    preset.loras = [LoRASelection(file: "t2.ckpt")]
    parameters = preset
    activator.remove("t2.ckpt", from: &parameters)
    #expect(parameters.steps == 30)
    #expect(activator.turbo.files.isEmpty)
  }

  @Test func aTurboOfAnotherFamilyIsAddedButNeverActivates() {
    let other = ModelCatalog(
      models: [],
      loras: [CatalogLoRA(file: "q.ckpt", name: "Q", family: "qwen_image", category: "turbo", steps: 4)], fileCount: 1)
    var parameters = start()
    var activator = LoRAActivator()
    activator.add(LoRASelection(file: "q.ckpt"), to: &parameters, catalog: other, family: "flux2_9b")
    #expect(parameters.loras.map(\.file) == ["q.ckpt"])
    #expect(parameters.steps == 20)
    #expect(activator.turbo.files.isEmpty)
    activator.add(LoRASelection(file: "q2.ckpt"), to: &parameters, catalog: other, family: "qwen_image")
    var ownFamily = start()
    var again = LoRAActivator()
    again.add(LoRASelection(file: "q.ckpt"), to: &ownFamily, catalog: other, family: "qwen_image")
    #expect(ownFamily.steps == 4)
  }
}
