import Foundation

/// Lo Shuffle (spec §6 di I4, adattato): al massimo tre categorie scelte a caso, con una voce ciascuna; la scelta precedente si
/// sostituisce. Foto/Arte decide quali categorie esistono.
enum F3Shuffler {
  static let maxCategories = 3

  static func pick(catalog: F3Catalog, mode: StyleMode, using generator: inout some RandomNumberGenerator) -> Set<String> {
    var picked = Set<String>()
    for category in catalog.categories(mode: mode).shuffled(using: &generator).prefix(maxCategories) {
      if let term = category.terms.randomElement(using: &generator) { picked.insert(term.id) }
    }
    return picked
  }
}
