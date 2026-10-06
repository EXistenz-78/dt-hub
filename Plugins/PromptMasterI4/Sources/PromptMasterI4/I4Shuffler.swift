import Foundation

/// The Shuffle (spec §6): in each section at most three categories, picked at random, with one term each; Medium and
/// Background one term in all. Photo/Art decides which categories exist. The description, the elements, the palette and
/// the mode are not touched, and the whole old selection is replaced.
enum I4Shuffler {
  /// The most categories a section gets: too much information makes a prompt worse.
  static let maxPerSection = 3

  static func pick(catalog: I4Catalog, mode: StyleMode, using generator: inout some RandomNumberGenerator) -> Set<String> {
    var picked = Set<String>()
    for field in [I4Field.aesthetics, .lighting, .style] {
      let categories = catalog.categories(for: field, mode: mode).filter { !$0.terms.isEmpty }
      for category in categories.shuffled(using: &generator).prefix(maxPerSection) {
        if let term = category.terms.randomElement(using: &generator) { picked.insert(term.id) }
      }
    }
    for field in [I4Field.medium, .background] {
      let pool = catalog.categories(for: field, mode: mode).flatMap(\.terms)
      if let term = pool.randomElement(using: &generator) { picked.insert(term.id) }
    }
    return picked
  }
}

extension I4Document {
  mutating func shuffle(catalog: I4Catalog, using generator: inout some RandomNumberGenerator) {
    selection = I4Shuffler.pick(catalog: catalog, mode: mode, using: &generator)
  }
}
