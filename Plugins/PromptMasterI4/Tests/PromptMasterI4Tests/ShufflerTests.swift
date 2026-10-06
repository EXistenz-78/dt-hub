import Foundation
import Testing

@testable import PromptMasterI4

@Suite("The Shuffle")
struct ShufflerTests {
  private let catalog = I4Catalog(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig)

  private func picks(_ mode: StyleMode, seed: UInt64) -> Set<String> {
    var generator = SeededGenerator(seed: seed)
    return I4Shuffler.pick(catalog: catalog, mode: mode, using: &generator)
  }

  @Test func eachSectionGetsAtMostThreeTermsFromDifferentCategoriesAndTheRulesOfTheListsHold() {
    for mode in [StyleMode.photo, .art] {
      for seed in 1...200 {
        let selection = picks(mode, seed: UInt64(seed))
        var document = I4Document()
        document.mode = mode
        document.selection = selection
        for field in [I4Field.aesthetics, .lighting, .style] {
          let terms = document.terms(in: field, catalog: catalog)
          #expect(terms.count == min(3, catalog.categories(for: field, mode: mode).count), "\(field) \(mode) \(seed)")
          // One per category: nothing chosen in a category is lost when the terms are read back by category.
          let inField = selection.filter { catalog.category(ofTerm: $0).flatMap { catalog.field(ofCategory: $0.id) } == field }
          #expect(inField.count == terms.count)
        }
        #expect(document.terms(in: .medium, catalog: catalog).count == 1, "medium \(mode) \(seed)")
        #expect(document.terms(in: .background, catalog: catalog).count == 1)
        // Nothing outside the lists of the mode.
        let shown = Set(I4Field.listed.flatMap { catalog.categories(for: $0, mode: mode) }.flatMap(\.terms).map(\.id))
          .union(catalog.categories(for: .background, mode: mode).flatMap(\.terms).map(\.id))
        #expect(selection.isSubset(of: shown))
      }
    }
  }

  @Test func theSameSeedGivesTheSameSelectionAndDifferentSeedsDiffer() {
    #expect(picks(.photo, seed: 5) == picks(.photo, seed: 5))
    #expect(Set((1...20).map { picks(.photo, seed: UInt64($0)) }).count > 10)
  }

  @Test func aSectionWithFewerThanThreeCategoriesUsesThemAll() {
    // Lighting has exactly three; give Medium (two in Photo) and a one-category section the same test via the catalog.
    let selection = picks(.photo, seed: 3)
    var document = I4Document()
    document.selection = selection
    #expect(document.terms(in: .lighting, catalog: catalog).count == 3)
    var config = I4Data.embeddedConfig
    config.fields["lighting"]?.common = ["light_source", "light_quality"]
    let small = I4Catalog(database: I4Data.embeddedDatabase, config: config)
    var generator = SeededGenerator(seed: 9)
    let pick = I4Shuffler.pick(catalog: small, mode: .photo, using: &generator)
    var other = I4Document()
    other.selection = pick
    #expect(other.terms(in: .lighting, catalog: small).count == 2)
  }

  @Test func theShuffleReplacesTheSelectionAndLeavesEverythingElseAlone() {
    var document = I4Document()
    document.description = "two friends"
    document.background = "a street"
    document.colors = ["#112233"]
    document.mode = .art
    document.addElement(type: .text)
    document.selection = ["fr_closeup"]
    let before = document
    var generator = SeededGenerator(seed: 11)
    document.shuffle(catalog: catalog, using: &generator)
    #expect(!document.selection.contains("fr_closeup") && !document.selection.isEmpty)
    var restored = document
    restored.selection = before.selection
    #expect(restored == before)
  }
}
