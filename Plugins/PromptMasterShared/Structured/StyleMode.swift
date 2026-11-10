import Foundation

/// Photo or Art: which categories the lists show.
enum StyleMode: String, Codable, Sendable { case photo, art }

/// How the plug-in asks the language model (the `options` of its configuration file).
struct LLMSettings: Codable, Equatable, Sendable {
  var temperature: Double
  var maxTokens: Int
  var thinking: Bool
  /// Seconds the plug-in waits for the answer.
  var timeout: Double
}
