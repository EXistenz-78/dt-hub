import Foundation

/// What Prompt Master knows about one family that the app's Family prompt does not say (`families.json`).
struct PMFamily: Codable, Equatable, Sendable {
  /// Categories that make no sense for the family; they do not appear in the list.
  var hiddenCategories: [String]
  /// What is added to the family's text when the "booru tags" switch is on (only for the families that have it).
  var booruSystem: String?
  /// The family's text is waiting for a review: the status line says so.
  var provisional: Bool?
  /// The family is written in tags: its Rules are `compose-tags.md` (the scene is enriched less).
  var tags: Bool?
}

/// `families.json`, keyed by the `version` Draw Things gives the family.
struct PMFamiliesData: Codable, Equatable, Sendable, VersionedData {
  var schema: Int
  var version: String
  var families: [String: PMFamily]
}

/// A term the user added to a category (spec §4): one string, in any language.
struct CustomTerm: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var categoryID: String
  var text: String
}

enum PMFamilies {
  /// The families the plug-in works with (on the others it is switched off and its tab is hidden), in the order of the spec §3.
  static let all = [
    "flux1", "flux2", "flux2_9b", "flux2_4b", "krea_2", "qwen_image", "qwen_image_2.1", "z_image",
    "sdxl_base_v0.9", "v1", "ernie_image", "hidream_i1", "cosmos2.5_2b",
  ]
  /// Families with the "booru tags" switch: Pony and Illustrious are SDXL and SD 1.5 for Draw Things.
  static let withBooruSwitch: Set<String> = ["sdxl_base_v0.9", "v1"]
}
