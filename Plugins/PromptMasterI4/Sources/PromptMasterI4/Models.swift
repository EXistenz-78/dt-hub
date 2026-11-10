import Foundation

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

/// `ideogram4.json` (spec §3): which categories feed each field and the settings of the language model. The master prompt
/// is a Markdown file of its own since 1.2 (`I4Prompts`).
struct IdeogramConfig: Codable, Equatable, Sendable, VersionedData {
  var schema: Int
  var version: String
  var fields: [String: FieldCategories]
  var mergedMood: MergedCategory
  var options: LLMSettings

  func categories(for field: I4Field) -> FieldCategories { fields[field.rawValue] ?? FieldCategories() }
}
