import Foundation

/// Quello che l'utente ha scritto e scelto nel tab (spec §5, §11).
struct F3Document: Codable, Equatable, Sendable {
  var description = ""
  /// Le voci scelte nel database (id), una per categoria.
  var selection: Set<String> = []
  var mode: StyleMode = .photo
  var composition = ""
  var elements: [F3Element] = []
  /// L'ultima fotografia prima di una scrittura dell'LLM; `nil` quando non c'è nulla da annullare.
  var snapshot: F3Snapshot?

  /// Sceglie (o toglie) una voce: una sola per categoria; una voce di una categoria non mostrata da `mode` non si sceglie.
  mutating func choose(_ termID: String, catalog: F3Catalog) {
    guard let category = catalog.category(ofTerm: termID),
      catalog.categories(mode: mode).contains(where: { $0.id == category.id })
    else { return }
    if selection.contains(termID) {
      selection.remove(termID)
      return
    }
    selection.subtract(category.terms.map(\.id))
    selection.insert(termID)
  }

  /// Foto ↔ Arte: gli elenchi cambiano e le scelte delle categorie che spariscono se ne vanno con loro.
  mutating func setMode(_ newMode: StyleMode, catalog: F3Catalog) {
    mode = newMode
    let shown = Set(catalog.categories(mode: newMode).flatMap { $0.terms.map(\.id) })
    selection.formIntersection(shown)
  }

  mutating func moveElement(_ id: String, by step: Int) {
    guard let index = elements.firstIndex(where: { $0.id == id }), elements.indices.contains(index + step) else { return }
    elements.swapAt(index, index + step)
  }

  func element(_ id: String) -> F3Element? { elements.first { $0.id == id } }
}
