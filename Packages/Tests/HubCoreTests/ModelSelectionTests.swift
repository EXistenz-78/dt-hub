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
}
