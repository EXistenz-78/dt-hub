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

/// `prompt-database.json`: shared with the Prompt Master plug-in (spec §3). This plug-in never writes it.
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

/// What an element of the caption is: something in the picture, or lettering in it.
enum ElementType: String, Codable, Sendable { case obj, text }

/// The parts of the caption that are filled from the vocabulary. `lettering` is the menu of a text element.
enum I4Field: String, CaseIterable, Codable, Sendable {
  case aesthetics, lighting, style, medium, background, lettering

  /// The fields that have a list of their own on the left (the lettering menu is on the element).
  static let listed: [I4Field] = [.aesthetics, .lighting, .style, .medium]
}

/// The categories that feed one field. `common` always, `photoOnly` only in Photo mode, `photo` and `art` by mode.
struct FieldCategories: Codable, Equatable, Sendable {
  var common: [String]?
  var photoOnly: [String]?
  var photo: [String]?
  var art: [String]?

  func ids(for mode: StyleMode) -> [String] {
    (common ?? []) + (mode == .photo ? (photoOnly ?? []) + (photo ?? []) : (art ?? []))
  }
}

/// The category made by merging two of the database (the Mood of the old Prompt Master).
struct MergedCategory: Codable, Equatable, Sendable {
  var id: String
  var it: String
  var en: String
  var from: [String]
}

/// `ideogram4.json` (spec §3): which categories feed each field, the settings of the language model and the master
/// prompt.
struct IdeogramConfig: Codable, Equatable, Sendable, VersionedData {
  var schema: Int
  var version: String
  var fields: [String: FieldCategories]
  var mergedMood: MergedCategory
  var options: LLMSettings
  var system: String

  struct LLMSettings: Codable, Equatable, Sendable {
    var temperature: Double
    var maxTokens: Int
    var thinking: Bool
    /// Seconds the plug-in waits for the answer.
    var timeout: Double
  }

  func categories(for field: I4Field) -> FieldCategories { fields[field.rawValue] ?? FieldCategories() }
}
