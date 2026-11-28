import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct ModelSelectionTests {
  let klein = CatalogModel(file: "flux_2_klein_9b_f16.ckpt", name: "FLUX.2 [klein] 9B", family: "flux2_9b")

  func freshDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "ModelSelectionTests-\(UUID())"))
  }

  @Test func startsWithNothingSelected() throws {
    #expect(ModelSelection(defaults: try freshDefaults()).selectedFile == nil)
  }

  @Test func remembersTheSelectionAcrossLaunches() throws {
    let defaults = try freshDefaults()
    ModelSelection(defaults: defaults).select(klein.file)
    #expect(ModelSelection(defaults: defaults).selectedFile == klein.file)
  }

  @Test func resolvesTheSelectedModelOnlyWhenInstalled() throws {
    let selection = ModelSelection(defaults: try freshDefaults())
    selection.select(klein.file)
    #expect(selection.selectedModel(in: ModelCatalog(models: [klein], loras: [], fileCount: 1)) == klein)
    #expect(selection.selectedModel(in: .empty) == nil)
    #expect(selection.selectedFile == klein.file)
  }

  /// An empty name is "no model" for RUN, so it must also be "no model" for the header.
  @Test func anEmptyNameMeansNothingSelected() throws {
    let defaults = try freshDefaults()
    defaults.set("", forKey: ModelSelection.key)
    #expect(ModelSelection(defaults: defaults).selectedFile == nil)

    let selection = ModelSelection(defaults: defaults)
    selection.select(klein.file)
    selection.select("")
    #expect(selection.selectedFile == nil)
    #expect(ModelSelection(defaults: defaults).selectedFile == nil)
  }

  @Test func choosingAnotherH3ModelAppliesVideoDefaults() throws {
    let h3 = CatalogModel(file: "minimax_h3_ref2va_i4x.ckpt", name: "H3", family: "minimax_h3")
    let catalog = ModelCatalog(models: [h3, klein], loras: [], fileCount: 2)
    let selection = ModelSelection(defaults: try freshDefaults())
    selection.select(klein.file)
    let result = selection.choose(h3.file, applyingTo: GenerationParameters(), from: .empty, in: catalog)
    #expect(result?.steps == 50)
    #expect(result?.width == 576)
  }

  /// SeedVR2 shifts tone and contrast unless the result is calibrated on the source image (as SeedVR2's own
  /// pipeline and SeedVR2-MLX do), so choosing it turns Color calibration on, with or without a table entry.
  @Test func choosingSeedVR2TurnsColorCalibrationOn() throws {
    let seedvr = CatalogModel(file: "seedvr2_7b_q8p.ckpt", name: "SeedVR2 7B", family: "seedvr2_7b")
    let catalog = ModelCatalog(models: [seedvr, klein], loras: [], fileCount: 2)
    let selection = ModelSelection(defaults: try freshDefaults())
    selection.select(klein.file)
    let result = selection.choose(seedvr.file, applyingTo: GenerationParameters(), from: .empty, in: catalog)
    #expect(result?.advanced.colorCalibration == true)
  }

  /// Leaving SeedVR2 turns it off again: on another model's image-to-image it would pull the colors back to the start image.
  @Test func leavingSeedVR2TurnsColorCalibrationOff() throws {
    let seedvr = CatalogModel(file: "seedvr2_3b_q8p.ckpt", name: "SeedVR2 3B", family: "seedvr2_3b")
    let catalog = ModelCatalog(models: [seedvr, klein], loras: [], fileCount: 2)
    let selection = ModelSelection(defaults: try freshDefaults())
    selection.select(seedvr.file)
    var parameters = GenerationParameters()
    parameters.advanced.colorCalibration = true
    let result = selection.choose(klein.file, applyingTo: parameters, from: .empty, in: catalog)
    #expect(result?.advanced.colorCalibration == false)
  }

  /// Between two other models the user's choice stays as it is.
  @Test func otherModelsKeepTheColorCalibrationAsItIs() throws {
    let qwen = CatalogModel(file: "qwen_image_2.1_q8p.ckpt", name: "Qwen", family: "qwen_image")
    let catalog = ModelCatalog(models: [qwen, klein], loras: [], fileCount: 2)
    let selection = ModelSelection(defaults: try freshDefaults())
    selection.select(qwen.file)
    var parameters = GenerationParameters()
    parameters.advanced.colorCalibration = true
    let result = selection.choose(klein.file, applyingTo: parameters, from: .empty, in: catalog)
    #expect((result ?? parameters).advanced.colorCalibration == true)
  }

  @Test func choosingTheSameVideoModelTwiceReturnsNilTheSecondTime() throws {
    let h3 = CatalogModel(file: "minimax_h3_ref2va_i4x.ckpt", name: "H3", family: "minimax_h3")
    let catalog = ModelCatalog(models: [h3], loras: [], fileCount: 1)
    let selection = ModelSelection(defaults: try freshDefaults())
    #expect(selection.choose(h3.file, applyingTo: GenerationParameters(), from: .empty, in: catalog) != nil)
    #expect(selection.choose(h3.file, applyingTo: GenerationParameters(), from: .empty, in: catalog) == nil)
  }
}
