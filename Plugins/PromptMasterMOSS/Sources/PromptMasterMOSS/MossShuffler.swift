import Foundation

/// Lo Shuffle (spec §6 di I4, adattato): al massimo tre categorie scelte a caso, con una voce ciascuna. Foto/Arte decide
/// quali categorie esistono; il negativo non entra mai (è nascosto dal catalogo).
enum MossShuffler {
  static let maxCategories = 3

  static func pick(catalog: MossCatalog, mode: StyleMode, using generator: inout some RandomNumberGenerator) -> Set<String> {
    var picked = Set<String>()
    for category in catalog.categories(mode: mode).shuffled(using: &generator).prefix(maxCategories) {
      if let term = category.terms.randomElement(using: &generator) { picked.insert(term.id) }
    }
    return picked
  }
}
