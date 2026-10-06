import Foundation

/// The vocabulary as the caption uses it: for each field and mode the categories to show, the Mood made of two
/// categories of the database, and where every term belongs.
struct I4Catalog {
  private let byID: [String: PMCategory]
  private let fieldOfCategory: [String: I4Field]
  private let categoryOfTerm: [String: String]
  let config: IdeogramConfig
  /// Categories the configuration names and the database does not have (the field simply lacks them).
  let missingCategories: [String]

  init(database: PromptDatabase, config: IdeogramConfig) {
    self.config = config
    var categories = Dictionary(uniqueKeysWithValues: database.categories.map { ($0.id, $0) })
    let merged = config.mergedMood
    var seen = Set<String>()
    var mergedTerms: [PMTerm] = []
    for id in merged.from {
      for term in categories[id]?.terms ?? [] where seen.insert(Self.key(term.en)).inserted { mergedTerms.append(term) }
    }
    if !mergedTerms.isEmpty {
      categories[merged.id] = PMCategory(
        id: merged.id, group: categories[merged.from.first ?? ""]?.group ?? "", it: merged.it, en: merged.en,
        descIt: nil, negative: nil, terms: mergedTerms)
    }
    var fieldOf: [String: I4Field] = [:]
    var missing: [String] = []
    var termOf: [String: String] = [:]
    for field in I4Field.allCases {
      let spec = config.categories(for: field)
      for id in (spec.common ?? []) + (spec.photoOnly ?? []) + (spec.photo ?? []) + (spec.art ?? []) {
        guard let category = categories[id] else {
          if !missing.contains(id) { missing.append(id) }
          continue
        }
        fieldOf[id] = field
        for term in category.terms { termOf[term.id] = id }
      }
    }
    byID = categories
    fieldOfCategory = fieldOf
    categoryOfTerm = termOf
    missingCategories = missing
  }

  private static func key(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces).lowercased() }

  /// The categories a field shows in `mode`, in the order of the configuration; those the database lacks are left out.
  func categories(for field: I4Field, mode: StyleMode) -> [PMCategory] {
    config.categories(for: field).ids(for: mode).compactMap { byID[$0] }
  }

  func category(ofTerm id: String) -> PMCategory? { categoryOfTerm[id].flatMap { byID[$0] } }

  func field(ofCategory id: String) -> I4Field? { fieldOfCategory[id] }

  func term(_ id: String) -> PMTerm? { category(ofTerm: id)?.terms.first { $0.id == id } }

  /// The menu of a text element (Text & Lettering).
  var lettering: [PMTerm] { categories(for: .lettering, mode: .photo).flatMap(\.terms) }
}
