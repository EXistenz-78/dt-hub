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

/// `prompt-database.json`: shared by the Prompt Master plug-ins (spec §3).
struct PromptDatabase: Codable, Equatable, Sendable, VersionedData {
  var schema: Int
  var version: String
  var groups: [PMGroup]
  var categories: [PMCategory]
}

/// The master prompt of one family and what goes with it.
struct FamilyPrompt: Codable, Equatable, Sendable {
  var label: String
  /// The family reads a negative prompt: the language model is asked for one too.
  var negative: Bool
  /// Categories that make no sense for the family; they do not appear in the list.
  var hiddenCategories: [String]
  var words: String
  /// The system prompt, in English, which asks for an English-only answer.
  var system: String
  /// What is added to `system` when the "booru tags" switch is on (only for the families that have it).
  var booruSystem: String?
  /// Written from the old notes only, waiting for the review of the spec §9.
  var provisional: Bool?
}

/// `master-prompts.json`, keyed by the `version` Draw Things gives the family.
struct MasterPrompts: Codable, Equatable, Sendable, VersionedData {
  var schema: Int
  var version: String
  var families: [String: FamilyPrompt]
}

/// A term the user added to a category (spec §4): one string, in any language.
struct CustomTerm: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var categoryID: String
  var text: String
}

enum PMFamilies {
  /// The families the plug-in works with (the tab is grey on the others), in the order of the spec §3.
  static let all = [
    "flux1", "flux2", "flux2_9b", "flux2_4b", "krea_2", "qwen_image", "qwen_image_2.1", "z_image",
    "sdxl_base_v0.9", "v1", "ernie_image", "hidream_i1", "cosmos2.5_2b",
  ]
  /// Families with the "booru tags" switch: Pony and Illustrious are SDXL and SD 1.5 for Draw Things.
  static let withBooruSwitch: Set<String> = ["sdxl_base_v0.9", "v1"]
}
