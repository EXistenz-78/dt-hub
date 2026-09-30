import Testing

@testable import HubKit

struct ModelCatalogTests {
  let klein = CatalogModel(file: "flux_2_klein_9b_f16.ckpt", name: "FLUX.2 [klein] 9B", family: "flux2_9b")
  let kleinKV = CatalogModel(file: "flux_2_klein_9b_kv_q8p.ckpt", name: "FLUX.2 [klein] 9B KV", family: "flux2_9b")
  let qwen = CatalogModel(file: "qwen_image_2.1_q8p.ckpt", name: "Qwen Image 2.1", family: "qwen_image_2.1")
  let mystery = CatalogModel(file: "custom.ckpt", name: "Custom", family: nil)

  @Test func emptyCatalogReportsModelBrowsingDisabled() {
    #expect(ModelCatalog.empty.isModelBrowsingDisabled)
    #expect(!ModelCatalog(models: [], loras: [], fileCount: 3).isModelBrowsingDisabled)
  }

  @Test func findsModelByFile() {
    let catalog = ModelCatalog(models: [klein, qwen], loras: [], fileCount: 2)
    #expect(catalog.model(forFile: qwen.file) == qwen)
    #expect(catalog.model(forFile: "missing.ckpt") == nil)
  }

  @Test func groupsModelsByFamilyWithUnknownFamilyLast() {
    let catalog = ModelCatalog(models: [mystery, qwen, kleinKV, klein], loras: [], fileCount: 4)
    #expect(catalog.modelsByFamily.map(\.family) == ["flux2_9b", "qwen_image_2.1", nil])
    #expect(catalog.modelsByFamily[0].models == [klein, kleinKV])
  }
}
