import Testing

@testable import PromptMasterF3

struct ShufflerTests {
  let catalog = F3Catalog(database: F3Data.embeddedDatabase, config: F3Data.embeddedConfig)

  @Test func atMostThreeCategoriesOneTermEach() {
    var generator = SystemRandomNumberGenerator()
    for mode in [StyleMode.photo, .art] {
      for _ in 0..<50 {
        let picked = F3Shuffler.pick(catalog: catalog, mode: mode, using: &generator)
        #expect(picked.count == F3Shuffler.maxCategories)
        #expect(catalog.choices(picked, mode: mode).count == picked.count)
      }
    }
  }
}
