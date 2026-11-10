import Foundation

/// One term of the vocabulary: its id (stable, also the key of a selection), its Italian and English names. The
/// English name is what the language model gets; the Italian one is for the interface.
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
  /// The group of technical terms (quality, negative, text): the Shuffle leaves it alone.
  var restricted: Bool?
}

/// `prompt-database.json`: the vocabulary shared by the Prompt Master plug-ins. Only Prompt Master writes it.
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
