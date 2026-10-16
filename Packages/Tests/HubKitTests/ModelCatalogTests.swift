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

  func model(_ file: String, family: String?, source: ModelSource?) -> CatalogModel {
    CatalogModel(file: file, name: file, family: family, source: source)
  }

  @Test func modelsBySourceGroupsInTheFixedOrder() {
    let catalog = ModelCatalog(
      models: [
        model("c.ckpt", family: "flux2_9b", source: .community), model("o.ckpt", family: "flux1", source: .official),
        model("u.ckpt", family: "flux1", source: .uncurated), model("none.ckpt", family: "flux1", source: nil),
      ], loras: [], fileCount: 4)
    #expect(catalog.modelsBySource.map(\.source) == [.official, .community, .uncurated])
    let all = catalog.modelsBySource.flatMap(\.families).flatMap(\.models).map(\.file)
    #expect(!all.contains("none.ckpt"))
  }

  @Test func theSameFamilyIsASeparateGroupInEachSource() {
    let catalog = ModelCatalog(
      models: [
        model("c1.ckpt", family: "flux1", source: .community), model("u1.ckpt", family: "flux1", source: .uncurated),
        model("u2.ckpt", family: "flux1", source: .uncurated),
      ], loras: [], fileCount: 3)
    let groups = catalog.modelsBySource
    #expect(groups.map(\.count) == [1, 2])
    #expect(groups[0].families.map(\.family) == ["flux1"] && groups[1].families.map(\.family) == ["flux1"])
  }

  @Test func anEmptySourceHasNoGroup() {
    let catalog = ModelCatalog(models: [model("c.ckpt", family: "flux1", source: .community)], loras: [], fileCount: 1)
    #expect(catalog.modelsBySource.map(\.source) == [.community])
  }

  @Test func settingTheSourceKeepsTheRest() {
    let changed = qwen.with(source: .official, isRemote: true)
    #expect(changed.file == qwen.file && changed.name == qwen.name && changed.family == qwen.family)
    #expect(changed.capabilities == qwen.capabilities)
    #expect(changed.source == .official && changed.isRemote)
  }

  @Test func theSourcesAreOrderedForDisplay() {
    #expect(ModelSource.allCases == [.official, .community, .uncurated])
    #expect(ModelSource.official < .community && ModelSource.community < .uncurated)
  }
}
