import HubKit
import Testing

@testable import HubCore

struct ModelTreeTests {
  func model(_ file: String, name: String? = nil, family: String?, _ source: ModelSource) -> CatalogModel {
    CatalogModel(file: file, name: name ?? file, family: family, source: source)
  }

  var catalog: ModelCatalog {
    ModelCatalog(
      models: [
        model("flux_1_schnell_q8p.ckpt", name: "FLUX.1 [schnell]", family: "flux1", .official),
        model("flux_1_dev_q8p.ckpt", name: "FLUX.1 [dev]", family: "flux1", .official),
        model("qwen_image_2.1_q8p.ckpt", name: "Qwen Image 2.1", family: "qwen_image_2.1", .community),
        model("some_flux_finetune_f16.ckpt", name: "Some Finetune", family: "flux1", .community),
        model("sdxl_thing_f16.ckpt", name: "Thing XL", family: "sdxl_base_v0.9", .uncurated),
        model("flux_other_f16.ckpt", name: "Other Flux", family: "flux1", .uncurated),
      ], loras: [], fileCount: 6)
  }

  @Test func theInitialStateOpensOnlyOfficial() {
    let sections = ModelTree.sections(for: catalog, query: "", state: ModelTreeState())
    #expect(sections.map(\.source) == [.official, .community, .uncurated])
    #expect(sections.map(\.isExpanded) == [true, false, false])
    #expect(sections.flatMap(\.families).allSatisfy { !$0.isExpanded })
  }

  @Test func countsAreTheModelsOfEachGroup() {
    let sections = ModelTree.sections(for: catalog, query: "", state: ModelTreeState())
    #expect(sections.map(\.count) == [2, 2, 2])
    #expect(sections[0].families.map(\.count) == [2])
  }

  @Test func familiesAreInNaturalOrderAndModelsByName() {
    let sections = ModelTree.sections(for: catalog, query: "", state: ModelTreeState())
    #expect(sections[1].families.map(\.family) == ["flux1", "qwen_image_2.1"])
    #expect(sections[0].families[0].models.map(\.name) == ["FLUX.1 [dev]", "FLUX.1 [schnell]"])
  }

  @Test func togglingASourceOrAFamilyChangesOnlyIt() {
    var state = ModelTreeState()
    state.toggle(.community)
    state.toggle(ModelTreeFamilyID(source: .community, family: "flux1"))
    var sections = ModelTree.sections(for: catalog, query: "", state: state)
    #expect(sections.map(\.isExpanded) == [true, true, false])
    #expect(sections[1].families.map(\.isExpanded) == [true, false])
    state.toggle(.community)
    sections = ModelTree.sections(for: catalog, query: "", state: state)
    #expect(sections[1].isExpanded == false)
  }

  @Test func theSameFamilyInTwoSourcesHasItsOwnState() {
    // Review focus 4: flux1 is in Community and in Uncurated.
    var state = ModelTreeState()
    state.toggle(ModelTreeFamilyID(source: .community, family: "flux1"))
    let sections = ModelTree.sections(for: catalog, query: "", state: state)
    let community = sections[1].families.first { $0.family == "flux1" }
    let uncurated = sections[2].families.first { $0.family == "flux1" }
    #expect(community?.isExpanded == true && uncurated?.isExpanded == false)
    #expect(community?.count == 1 && uncurated?.count == 1)
  }

  @Test func searchMatchesNameFileAndFamily() {
    let state = ModelTreeState()
    #expect(files(ModelTree.sections(for: catalog, query: "schnell", state: state)) == ["flux_1_schnell_q8p.ckpt"])
    #expect(files(ModelTree.sections(for: catalog, query: "finetune_f16", state: state)) == ["some_flux_finetune_f16.ckpt"])
    #expect(files(ModelTree.sections(for: catalog, query: "sdxl_base", state: state)) == ["sdxl_thing_f16.ckpt"])
  }

  func files(_ sections: [ModelTreeSection]) -> [String] {
    sections.flatMap(\.families).flatMap(\.models).map(\.file)
  }

  @Test func searchIgnoresCaseAndAccents() {
    // Review focus 3.
    let state = ModelTreeState()
    let found = files(ModelTree.sections(for: catalog, query: "FLÜX.1", state: state))
    #expect(Set(found) == ["flux_1_schnell_q8p.ckpt", "flux_1_dev_q8p.ckpt"])
  }

  @Test func onlySpacesIsNoSearch() {
    let state = ModelTreeState()
    let plain = ModelTree.sections(for: catalog, query: "", state: state)
    #expect(ModelTree.sections(for: catalog, query: "   ", state: state) == plain)
  }

  @Test func searchOpensEveryGroupWithResultsAndHidesTheRest() {
    let sections = ModelTree.sections(for: catalog, query: "flux", state: ModelTreeState())
    #expect(sections.map(\.source) == [.official, .community, .uncurated])
    #expect(sections.allSatisfy(\.isExpanded) && sections.flatMap(\.families).allSatisfy(\.isExpanded))
    #expect(sections.map(\.count) == [2, 1, 1])
    let narrow = ModelTree.sections(for: catalog, query: "qwen", state: ModelTreeState())
    #expect(narrow.map(\.source) == [.community])
  }

  @Test func clearingTheSearchGoesBackToTheState() {
    var state = ModelTreeState()
    state.toggle(.uncurated)
    let before = ModelTree.sections(for: catalog, query: "", state: state)
    _ = ModelTree.sections(for: catalog, query: "flux", state: state)
    #expect(ModelTree.sections(for: catalog, query: "", state: state) == before)
  }

  @Test func noResultsGivesNoSections() {
    #expect(ModelTree.sections(for: catalog, query: "zzz", state: ModelTreeState()).isEmpty)
  }

  @Test func aSourceWithoutModelsIsOmitted() {
    let only = ModelCatalog(models: [model("a.ckpt", family: nil, .uncurated)], loras: [], fileCount: 1)
    let sections = ModelTree.sections(for: only, query: "", state: ModelTreeState())
    #expect(sections.map(\.source) == [.uncurated])
    #expect(sections[0].families.map(\.family) == [nil])
  }

  var catalogWithVideo: ModelCatalog {
    ModelCatalog(
      models: [
        model("flux_1_dev_q8p.ckpt", name: "FLUX.1 [dev]", family: "flux1", .official),
        model("wan_2.1_14b_t2v_q8p.ckpt", name: "Wan 2.1 14B", family: "wan_v2.1_14b", .official),
        model("minimax_h3_q8p.ckpt", name: "MiniMax H3", family: "minimax_h3", .official),
        model("ltx_2.3_q8p.ckpt", name: "LTX 2.3", family: "ltx2.3", .uncurated),
      ], loras: [], fileCount: 4)
  }

  @Test func onlyTheEnabledVideoFamiliesAreInTheTree() {
    // The picker leaves out the video families not enabled yet (they stay in the catalog).
    let sections = ModelTree.sections(for: catalogWithVideo, query: "", state: ModelTreeState())
    #expect(files(sections) == ["flux_1_dev_q8p.ckpt", "minimax_h3_q8p.ckpt", "ltx_2.3_q8p.ckpt"])
    #expect(sections.map(\.count) == [2, 1])
    #expect(catalogWithVideo.models.count == 4)
  }

  @Test func searchFindsEnabledVideoModelsButNeverHiddenOnes() {
    #expect(ModelTree.sections(for: catalogWithVideo, query: "wan", state: ModelTreeState()).isEmpty)
    #expect(files(ModelTree.sections(for: catalogWithVideo, query: "ltx", state: ModelTreeState())) == ["ltx_2.3_q8p.ckpt"])
    #expect(
      files(ModelTree.sections(for: catalogWithVideo, query: "minimax", state: ModelTreeState()))
        == ["minimax_h3_q8p.ckpt"])
  }
}
