import Foundation

struct MossCatalogGroup: Identifiable, Equatable, Sendable {
  var group: PMGroup
  var categories: [PMCategory]
  var id: String { group.id }
}

/// Il vocabolario come lo usa MOSS (spec §4): tutti i gruppi; Foto/Arte decide quali categorie compaiono; le categorie di
/// medium e genere vanno in `meta`, le altre nella caption; il negativo ha una lista a parte.
struct MossCatalog: Sendable, MossTerms {
  let database: PromptDatabase
  let config: MossConfig
  private let byID: [String: PMCategory]
  private let categoryOfTerm: [String: String]

  init(database: PromptDatabase, config: MossConfig) {
    self.database = database
    self.config = config
    byID = Dictionary(uniqueKeysWithValues: database.categories.map { ($0.id, $0) })
    var termOf: [String: String] = [:]
    for category in database.categories { for term in category.terms { termOf[term.id] = category.id } }
    categoryOfTerm = termOf
  }

  /// Le categorie che la configurazione nomina e il database non ha (si ignorano; il test le segnala).
  var unknownCategories: [String] {
    (config.hiddenCategories + config.photoOnly + config.artOnly + config.metaCategories).filter { byID[$0] == nil }
  }

  /// Le categorie che `mode` mostra, nell'ordine del database.
  func categories(mode: StyleMode) -> [PMCategory] {
    let hidden = Set(config.hiddenCategories + (mode == .photo ? config.artOnly : config.photoOnly))
    return database.categories.filter { !hidden.contains($0.id) && !$0.terms.isEmpty }
  }

  func groups(mode: StyleMode) -> [MossCatalogGroup] {
    let shown = categories(mode: mode)
    return database.groups.compactMap { group in
      let own = shown.filter { $0.group == group.id }
      return own.isEmpty ? nil : MossCatalogGroup(group: group, categories: own)
    }
  }

  func category(ofTerm id: String) -> PMCategory? { categoryOfTerm[id].flatMap { byID[$0] } }

  /// Le voci scelte, una per categoria, nell'ordine del database, tra le categorie per cui `include` è vero.
  private func chosen(_ selection: Set<String>, where include: (PMCategory) -> Bool) -> [String] {
    database.categories.compactMap { category in
      guard include(category) else { return nil }
      return category.terms.first { selection.contains($0.id) }?.en
    }
  }

  func metaTerms(_ selection: Set<String>) -> [String] {
    let meta = Set(config.metaCategories)
    return chosen(selection) { meta.contains($0.id) }
  }

  func captionTerms(_ selection: Set<String>) -> [String] {
    let excluded = Set(config.metaCategories + config.hiddenCategories)
    return chosen(selection) { !excluded.contains($0.id) }
  }

  /// Le voci del negativo: i termini aggiunti dal plug-in, poi i venticinque del database.
  var negativeChoices: [PMTerm] {
    config.extraNegativeTerms + (byID["negative_terms"]?.terms.filter { term in !config.extraNegativeTerms.contains { $0.en == term.en } } ?? [])
  }

  func negativeTerms(_ selection: Set<String>) -> [String] { negativeChoices.filter { selection.contains($0.id) }.map(\.en) }
}

extension MossDocument {
  /// Cambia Foto/Arte e toglie le voci delle categorie che il nuovo modo nasconde.
  mutating func setMode(_ newMode: StyleMode, catalog: MossCatalog) {
    mode = newMode
    let visible = Set(catalog.categories(mode: newMode).flatMap { $0.terms.map(\.id) })
    selection = selection.filter { visible.contains($0) }
  }
}
