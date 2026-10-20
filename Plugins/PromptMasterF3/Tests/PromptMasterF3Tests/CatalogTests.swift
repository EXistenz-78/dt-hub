import Testing

@testable import PromptMasterF3

struct CatalogTests {
  let catalog = F3Catalog(database: F3Data.embeddedDatabase, config: F3Data.embeddedConfig)

  @Test func groupHIsNeverShown() {
    for mode in [StyleMode.photo, .art] {
      let ids = Set(catalog.categories(mode: mode).map(\.id))
      #expect(ids.isDisjoint(with: ["render_quality", "negative_terms", "typography_text"]))
      #expect(!catalog.groups(mode: mode).contains { $0.group.id == "H" })
    }
  }

  @Test func photoShowsPhotoCategoriesAndNotArtOnes() {
    let ids = Set(catalog.categories(mode: .photo).map(\.id))
    #expect(ids.contains("framing") && ids.contains("photo_genre") && ids.contains("light_source"))
    #expect(!ids.contains("art_movement") && !ids.contains("medium_paint_draw"))
  }

  @Test func artShowsArtCategoriesAndNotPhotoOnes() {
    let ids = Set(catalog.categories(mode: .art).map(\.id))
    #expect(ids.contains("art_movement") && ids.contains("light_source"))
    #expect(!ids.contains("framing") && !ids.contains("film_stock_process"))
  }

  @Test func groupsKeepDatabaseOrderAndHaveCategories() {
    let groups = catalog.groups(mode: .photo)
    #expect(groups.first?.group.id == "A")
    #expect(groups.allSatisfy { !$0.categories.isEmpty })
  }

  @Test func choicesAreInCategoryOrderOnePerCategory() throws {
    let light = try #require(catalog.categories(mode: .photo).first { $0.id == "light_source" })
    let framing = try #require(catalog.categories(mode: .photo).first { $0.id == "framing" })
    let selection: Set<String> = [light.terms[0].id, framing.terms[0].id, framing.terms[1].id]
    let choices = catalog.choices(selection, mode: .photo)
    #expect(choices.map(\.category.id) == ["framing", "light_source"])
    #expect(choices.count == 2)
    #expect(catalog.termNames(selection, mode: .photo).first == framing.terms[0].en)
  }

  @Test func choicesOfHiddenCategoriesAreIgnored() throws {
    let art = try #require(catalog.categories(mode: .art).first { $0.id == "art_movement" })
    #expect(catalog.choices([art.terms[0].id], mode: .photo).isEmpty)
  }
}
