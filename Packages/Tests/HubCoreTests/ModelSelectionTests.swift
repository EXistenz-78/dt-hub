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

  @Test func choosingTheSameVideoModelTwiceReturnsNilTheSecondTime() throws {
    let h3 = CatalogModel(file: "minimax_h3_ref2va_i4x.ckpt", name: "H3", family: "minimax_h3")
    let catalog = ModelCatalog(models: [h3], loras: [], fileCount: 1)
    let selection = ModelSelection(defaults: try freshDefaults())
    #expect(selection.choose(h3.file, applyingTo: GenerationParameters(), from: .empty, in: catalog) != nil)
    #expect(selection.choose(h3.file, applyingTo: GenerationParameters(), from: .empty, in: catalog) == nil)
  }
}
