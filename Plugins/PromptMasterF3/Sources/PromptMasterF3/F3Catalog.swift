import Foundation

struct F3CatalogGroup: Identifiable, Equatable, Sendable {
  var group: PMGroup
  var categories: [PMCategory]
  var id: String { group.id }
}

struct F3Choice: Equatable, Sendable {
  var category: PMCategory
  var term: PMTerm
}

/// Il vocabolario come lo usa F3 (spec §4): tutti i gruppi tranne quelli esclusi (H «Technical»); Foto/Arte decide quali
/// categorie compaiono.
struct F3Catalog: Sendable {
  let database: PromptDatabase
  let config: F3Config
  private let categoryOfTerm: [String: String]
  private let byID: [String: PMCategory]

  init(database: PromptDatabase, config: F3Config) {
    self.database = database
    self.config = config
    byID = Dictionary(uniqueKeysWithValues: database.categories.map { ($0.id, $0) })
    var termOf: [String: String] = [:]
    for category in database.categories { for term in category.terms { termOf[term.id] = category.id } }
    categoryOfTerm = termOf
  }

  /// Le categorie che `mode` mostra, nell'ordine del database.
  func categories(mode: StyleMode) -> [PMCategory] {
    let hidden = Set(mode == .photo ? config.artOnly : config.photoOnly)
    return database.categories.filter { !config.excludedGroups.contains($0.group) && !hidden.contains($0.id) && !$0.terms.isEmpty }
  }

  /// I gruppi con le loro categorie, quelli senza categorie visibili esclusi.
  func groups(mode: StyleMode) -> [F3CatalogGroup] {
    let shown = categories(mode: mode)
    return database.groups.compactMap { group in
      let own = shown.filter { $0.group == group.id }
      return own.isEmpty ? nil : F3CatalogGroup(group: group, categories: own)
    }
  }

  func category(ofTerm id: String) -> PMCategory? { categoryOfTerm[id].flatMap { byID[$0] } }

  func term(_ id: String) -> PMTerm? { category(ofTerm: id)?.terms.first { $0.id == id } }

  /// Le voci scelte che `mode` mostra, nell'ordine delle categorie (una per categoria).
  func choices(_ selection: Set<String>, mode: StyleMode) -> [F3Choice] {
    categories(mode: mode).compactMap { category in
      category.terms.first { selection.contains($0.id) }.map { F3Choice(category: category, term: $0) }
    }
  }

  /// I nomi inglesi delle voci scelte: finiscono in coda alla descrizione quando non si usa l'LLM.
  func termNames(_ selection: Set<String>, mode: StyleMode) -> [String] { choices(selection, mode: mode).map(\.term.en) }
}
