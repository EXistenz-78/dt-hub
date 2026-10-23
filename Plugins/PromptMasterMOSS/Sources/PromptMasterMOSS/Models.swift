import Foundation

/// One term of the vocabulary: its id (stable, also the key of a selection), its Italian and English names. The
/// English name is what goes in the caption and to the language model.
struct PMTerm: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var it: String
  var en: String
}

struct PMCategory: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var group: String
  var it: String
  var en: String
  /// A line about the category, in Italian only (a tooltip).
  var descIt: String?
  /// The terms of this category are things to avoid, not things to include.
  var negative: Bool?
  var terms: [PMTerm]
}

struct PMGroup: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var it: String
  var en: String
  var restricted: Bool?
}

/// `prompt-database.json`: condiviso con Prompt Master (spec §4). Questo plug-in non lo scrive mai.
struct PromptDatabase: Codable, Equatable, Sendable, VersionedData {
  var schema: Int
  var version: String
  var groups: [PMGroup]
  var categories: [PMCategory]

  /// Group ids, category ids and term ids (across all categories) are each used once.
  var hasUniqueIDs: Bool {
    func unique(_ ids: [String]) -> Bool { Set(ids).count == ids.count }
    return unique(groups.map(\.id)) && unique(categories.map(\.id)) && unique(categories.flatMap { $0.terms.map(\.id) })
  }
}

/// Photo or Art: which categories the lists show (spec §5).
enum StyleMode: String, Codable, Sendable { case photo, art }
