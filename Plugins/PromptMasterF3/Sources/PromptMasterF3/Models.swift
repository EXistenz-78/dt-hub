import Foundation

/// `flux3.json`: i gruppi esclusi, le categorie solo-Foto e solo-Arte, le opzioni dell'LLM. Il master prompt è un file Markdown
/// a parte (`F3Prompts`).
struct F3Config: Codable, Equatable, Sendable, VersionedData {
  var schema: Int
  var version: String
  var excludedGroups: [String]
  var photoOnly: [String]
  var artOnly: [String]
  var options: LLMSettings
}
