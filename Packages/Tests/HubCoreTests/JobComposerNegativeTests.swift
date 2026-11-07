import HubKit
import Testing

@testable import HubCore

struct JobComposerNegativeTests {
  let flux = CatalogModel(file: "flux_2_klein_9b_f16.ckpt", name: "FLUX.2", family: "flux2_9b")
  let krea = CatalogModel(file: "krea_2.ckpt", name: "Krea 2", family: "krea_2")

  func negatives(_ model: CatalogModel) -> [String] {
    let catalog = ModelCatalog(models: [flux, krea], loras: [], fileCount: 2)
    return JobComposer.batches(
      prompt: "p", negativePrompt: "ugly, blurry", model: model.file, family: model.family,
      parameters: GenerationParameters(), catalog: catalog) { 1 }.map(\.negativePrompt)
  }

  @Test func aModelThatDoesNotReadItNeverGetsTheNegativePrompt() {
    #expect(negatives(flux).allSatisfy { $0.isEmpty })
  }

  @Test func aModelThatReadsItGetsIt() {
    let sent = negatives(krea)
    #expect(!sent.isEmpty)
    #expect(sent.allSatisfy { $0 == "ugly, blurry" })
  }
}
