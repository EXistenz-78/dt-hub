import Foundation
import Testing

@testable import PromptMaster

/// A generator that gives the same numbers for the same seed (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64
  init(_ seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

@Suite("The Shuffle")
struct ShufflerTests {
  private let database = PMData.embeddedDatabase

  private func categoryOf(_ termID: String) -> String? {
    database.categories.first { $0.terms.contains { $0.id == termID } }?.id
  }

  private func shuffle(_ mode: StyleMode, hidden: Set<String> = [], seed: UInt64 = 1) -> [String] {
    var generator = SeededGenerator(seed)
    return Shuffler.pick(database: database, hidden: hidden, mode: mode, using: &generator)
  }

  @Test func itIsTheSameForTheSameSeedAndDifferentForAnother() {
    #expect(shuffle(.photo, seed: 7) == shuffle(.photo, seed: 7))
    #expect(shuffle(.photo, seed: 7) != shuffle(.photo, seed: 8))
  }

  @Test func everyPickIsARealTermAndNoCategoryGivesTwoExceptTheMedium() {
    for mode in [StyleMode.photo, .art] {
      let ids = shuffle(mode)
      let categories = ids.compactMap(categoryOf)
      #expect(categories.count == ids.count)  // all real
      let medium = Set(mode == .photo ? Shuffler.photoMedium : Shuffler.artMedium)
      let outsideMedium = categories.filter { !medium.contains($0) }
      #expect(Set(outsideMedium).count == outsideMedium.count)
      #expect(categories.filter(medium.contains).count == 1)  // the medium is one draw from the union
    }
  }

  @Test func photoPicksPhotographicCategoriesAndArtPicksArtisticOnes() {
    let photo = Set(shuffle(.photo).compactMap(categoryOf))
    let art = Set(shuffle(.art).compactMap(categoryOf))
    #expect(Set(Shuffler.photoOnly).isSubset(of: photo) && photo.isDisjoint(with: Shuffler.artOnly))
    #expect(Set(Shuffler.artOnly).isSubset(of: art) && art.isDisjoint(with: Shuffler.photoOnly))
    #expect(photo.isSuperset(of: ["light_source", "mood", "environment_built"]) && art.isSuperset(of: ["light_source", "mood"]))
  }

  @Test func theTechnicalGroupIsNeverShuffled() {
    let technical = Set(database.categories.filter { $0.group == "H" }.map(\.id))
    for seed in 1...20 as ClosedRange<UInt64> {
      #expect(Set(shuffle(.photo, seed: seed).compactMap(categoryOf)).isDisjoint(with: technical))
    }
  }

  @Test func hiddenCategoriesAreSkippedAndTheMediumDrawsOnlyFromWhatIsLeft() {
    let hidden: Set<String> = ["lens_focus", "framing", "medium_digital_3d", "film_stock_process"]
    for seed in 1...20 as ClosedRange<UInt64> {
      let categories = shuffle(.photo, hidden: hidden, seed: seed).compactMap(categoryOf)
      #expect(Set(categories).isDisjoint(with: hidden))
    }
    let everything = Set(database.categories.map(\.id))
    #expect(shuffle(.photo, hidden: everything).isEmpty)
  }

  @Test func theMediumPoolHasTheTermsOfAllItsCategories() {
    var seen = Set<String>()
    for seed in 1...400 as ClosedRange<UInt64> {
      seen.formUnion(shuffle(.art, seed: seed).compactMap(categoryOf).filter(Shuffler.artMedium.contains))
    }
    #expect(seen == Set(Shuffler.artMedium))
  }
}
