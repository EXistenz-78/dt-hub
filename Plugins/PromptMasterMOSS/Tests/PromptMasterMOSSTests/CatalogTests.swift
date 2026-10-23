import Foundation
import Testing

@testable import PromptMasterMOSS

struct CatalogTests {
  let data = MossData.load(folder: URL(fileURLWithPath: "/nonexistent/DT Hub"))
  var catalog: MossCatalog { MossCatalog(database: data.database, config: data.config) }

  func termID(_ category: String, _ index: Int = 0) -> String {
    data.database.categories.first { $0.id == category }!.terms[index].id
  }

  @Test func negativeTermsNeverAppearInTheSummaryLists() {
    for mode in [StyleMode.photo, .art] {
      #expect(!catalog.categories(mode: mode).contains { $0.id == "negative_terms" })
    }
  }

  @Test func renderQualityAndLetteringAreInBothModes() {
    for mode in [StyleMode.photo, .art] {
      let ids = catalog.categories(mode: mode).map(\.id)
      #expect(ids.contains("render_quality") && ids.contains("typography_text"))
    }
  }

  @Test func photoShowsPhotoOnlyAndNotArtOnly_andViceVersa() {
    let photo = catalog.categories(mode: .photo).map(\.id)
    let art = catalog.categories(mode: .art).map(\.id)
    #expect(photo.contains("lens_focus") && !photo.contains("art_movement"))
    #expect(art.contains("art_movement") && !art.contains("lens_focus"))
  }

  @Test func metaCategoriesAreTheMediumAndGenreOnes_andAllExist() {
    #expect(data.config.metaCategories.count == 9)
    #expect(catalog.unknownCategories.isEmpty)
    #expect(data.config.metaCategories.contains("photo_genre") && data.config.metaCategories.contains("film_stock_process"))
  }

  @Test func chosenTermsAreSplitBetweenMetaAndCaption_inDatabaseOrder() {
    let photoGenre = termID("photo_genre"), source = termID("light_source"), quality = termID("render_quality")
    let selection: Set<String> = [photoGenre, source, quality]
    #expect(catalog.metaTerms(selection) == [data.database.categories.first { $0.id == "photo_genre" }!.terms[0].en])
    // light_source viene prima di render_quality nel database
    #expect(catalog.captionTerms(selection) == [
      data.database.categories.first { $0.id == "light_source" }!.terms[0].en,
      data.database.categories.first { $0.id == "render_quality" }!.terms[0].en,
    ])
  }

  @Test func onlyOneTermPerCategoryCounts() {
    let two: Set<String> = [termID("light_source", 0), termID("light_source", 1)]
    #expect(catalog.captionTerms(two).count == 1)
  }

  @Test func negativeListIsTheExtrasThenTheTwentyFiveOfTheDatabase() {
    let terms = catalog.negativeChoices
    #expect(terms.count == 27)
    #expect(terms.prefix(2).map(\.en) == ["worst quality", "low quality"])
    #expect(terms.filter { $0.en == "worst quality" }.count == 1)
    #expect(Set(terms.map(\.id)).count == terms.count)
  }

  @Test func theDefaultNegativeSelectionGivesTheOfficialTerms() {
    #expect(catalog.negativeTerms(MossDocument().negativeSelection) == ["worst quality", "bad anatomy"])
  }

  @Test func changingModeDropsTheTermsTheNewModeHides() {
    var document = MossDocument()
    document.selection = [termID("lens_focus"), termID("art_movement"), termID("light_source")]
    document.setMode(.art, catalog: catalog)
    #expect(document.mode == .art)
    #expect(document.selection == [termID("art_movement"), termID("light_source")])
  }

  @Test func configCategoriesMissingFromTheDatabaseAreReported() {
    var config = data.config
    config.metaCategories.append("not_a_category")
    #expect(MossCatalog(database: data.database, config: config).unknownCategories == ["not_a_category"])
  }
}
