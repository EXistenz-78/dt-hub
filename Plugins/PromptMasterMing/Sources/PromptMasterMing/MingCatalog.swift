import Foundation

struct MingCatalogGroup: Identifiable, Equatable, Sendable {
  var group: PMGroup
  var categories: [PMCategory]
  var id: String { group.id }
}

/// Il vocabolario come lo usa Ming: Foto/Arte decide quali categorie compaiono; le categorie della luce vanno in
/// `ambient_lighting`, le altre in `image_style`. Il negativo non c'è (Ming non lo legge).
struct MingCatalog: Sendable, MingTerms {
  let database: PromptDatabase
  let config: MingConfig
  private let byID: [String: PMCategory]
  private let categoryOfTerm: [String: String]

  init(database: PromptDatabase, config: MingConfig) {
    self.database = database
    self.config = config
    byID = Dictionary(uniqueKeysWithValues: database.categories.map { ($0.id, $0) })
    var termOf: [String: String] = [:]
    for category in database.categories { for term in category.terms { termOf[term.id] = category.id } }
    categoryOfTerm = termOf
  }

  /// Le categorie che la configurazione nomina e il database non ha (si ignorano; il test le segnala).
  var unknownCategories: [String] {
    (config.hiddenCategories + config.photoOnly + config.artOnly + config.lightingCategories).filter { byID[$0] == nil }
  }

  /// Le categorie che `mode` mostra, nell'ordine del database.
  func categories(mode: StyleMode) -> [PMCategory] {
    let hidden = Set(config.hiddenCategories + (mode == .photo ? config.artOnly : config.photoOnly))
    return database.categories.filter { !hidden.contains($0.id) && !$0.terms.isEmpty }
  }

  func groups(mode: StyleMode) -> [MingCatalogGroup] {
    let shown = categories(mode: mode)
    return database.groups.compactMap { group in
      let own = shown.filter { $0.group == group.id }
      return own.isEmpty ? nil : MingCatalogGroup(group: group, categories: own)
    }
  }

  func category(ofTerm id: String) -> PMCategory? { categoryOfTerm[id].flatMap { byID[$0] } }

  /// Vero per un gruppo fatto solo di categorie della luce (va sopra Ambient Lighting).
  func isLighting(_ group: MingCatalogGroup) -> Bool { !group.categories.isEmpty && group.categories.allSatisfy(isLighting) }

  private func isLighting(_ category: PMCategory) -> Bool { config.lightingCategories.contains(category.id) }
  private func isHidden(_ category: PMCategory) -> Bool { config.hiddenCategories.contains(category.id) }

  /// Le voci scelte, una per categoria, nell'ordine del database, tra le categorie per cui `include` è vero.
  private func chosen(_ selection: Set<String>, where include: (PMCategory) -> Bool) -> [PMTerm] {
    database.categories.compactMap { category in
      guard include(category) else { return nil }
      return category.terms.first { selection.contains($0.id) }
    }
  }

  func lightingTerms(_ selection: Set<String>) -> [String] { chosen(selection) { isLighting($0) && !isHidden($0) }.map(\.en) }
  func styleTerms(_ selection: Set<String>) -> [String] { chosen(selection) { !isLighting($0) && !isHidden($0) }.map(\.en) }

  /// Le righe `Categoria: voce` (categoria in inglese, voce in `en`): quello che l'LLM riceve.
  private func lines(_ selection: Set<String>, lighting: Bool) -> [String] {
    database.categories.compactMap { category in
      guard !isHidden(category), isLighting(category) == lighting,
        let term = category.terms.first(where: { selection.contains($0.id) })
      else { return nil }
      return "\(category.en): \(term.en)"
    }
  }

  func styleLines(_ selection: Set<String>) -> [String] { lines(selection, lighting: false) }
  func lightingLines(_ selection: Set<String>) -> [String] { lines(selection, lighting: true) }
}

extension MingDocument {
  /// Cambia Foto/Arte e toglie le voci delle categorie che il nuovo modo nasconde.
  mutating func setMode(_ newMode: StyleMode, catalog: MingCatalog) {
    mode = newMode
    let visible = Set(catalog.categories(mode: newMode).flatMap { $0.terms.map(\.id) })
    selection = selection.filter { visible.contains($0) }
  }

  /// Sceglie una voce: una sola per categoria (scegliere un'altra della stessa la sostituisce, scegliere la stessa la toglie).
  mutating func choose(_ termID: String, catalog: MingCatalog) {
    guard let category = catalog.category(ofTerm: termID) else { return }
    let wasChosen = selection.contains(termID)
    selection.subtract(category.terms.map(\.id))
    if !wasChosen { selection.insert(termID) }
  }
}
