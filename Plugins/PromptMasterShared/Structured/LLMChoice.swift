import DTHubPluginKit
import Foundation

/// Which language model a Prompt Master asks, from the assignments of Settings › LLM that the app sends with every model
/// (`family`, `use`). Without a name the app looks only at the models on "all others": a model assigned to the family would
/// be ignored and, with nobody on "all others", the request would fail.
enum LLMChoice {
  /// The uses that cover the Enhance button on a Control tab without pictures (as the app's router does).
  static let writingUses: Set<String> = ["enhance", "both", "t2i"]

  /// The name of the model assigned to `family` for writing prompts: the first by name, as the app's router does. nil = none for
  /// this family: ask without a name, and the app uses the one on "all others" (or says there is none: no default is invented).
  static func model(family: String?, languageModels: [DTHubLanguageModel]) -> String? {
    guard let family else { return nil }
    return languageModels
      .filter { $0.family == family && writingUses.contains($0.use ?? "") }
      .min { $0.name.localizedStandardCompare($1.name) == .orderedAscending }?.name
  }

  /// For the status tool: which model would be asked.
  static func description(family: String?, languageModels: [DTHubLanguageModel]) -> [String: Any] {
    if let name = model(family: family, languageModels: languageModels) { return ["kind": "assigned_to_family", "model": name] }
    return ["kind": "app_default", "note": "No LLM is assigned to this family: the app uses the one on 'all others', or says there is none."]
  }
}

/// Small helpers of the MCP tools of the structured Prompt Master plug-ins.
enum ToolSupport {
  struct Failure: Error { var text: String }

  /// "a, b\nc" → ["a", "b", "c"].
  static func ids(_ text: String?) -> [String] {
    (text ?? "").split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }

  static func null(_ value: Any?) -> Any { value ?? NSNull() }

  static func json(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    return String(decoding: data, as: UTF8.self)
  }

  /// Lower case, without accents.
  static func fold(_ text: String) -> String { text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }

  /// Every word of `query` is in `haystack`.
  static func matches(_ query: String, in haystack: [String]) -> Bool {
    let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    let text = fold(haystack.joined(separator: " "))
    return words.allSatisfy { text.contains($0) }
  }

  static let maxDescription = 4000
}
