import Foundation

/// What is sent to the language model: the system prompt and the request.
struct Brief: Equatable {
  var system: String
  var prompt: String
}

enum BriefBuilder {
  /// The request: the description as the user wrote it (any language), then the terms in English, those to include
  /// and those to avoid. The same text goes to the generic model and to a prompt enhancer.
  static func request(description: String, terms: [SelectedTerm]) -> String {
    let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
    var lines = ["Description (any language):", text.isEmpty ? "(none: build the image from the terms alone)" : text]
    let include = terms.filter { !$0.isNegative }
    let avoid = terms.filter(\.isNegative)
    if !include.isEmpty {
      lines += ["", "Terms to include:"] + include.map { "- \($0.english)" }
    }
    if !avoid.isEmpty {
      lines += ["", "Terms to avoid:"] + avoid.map { "- \($0.english)" }
    }
    return lines.joined(separator: "\n")
  }

  /// The brief for a family's master prompt; nil for a family without one. `booru` adds the tag rule, for the two
  /// families that have the switch.
  static func make(
    family: String, masters: MasterPrompts, description: String, terms: [SelectedTerm], booru: Bool
  ) -> Brief? {
    guard let master = masters.families[family] else { return nil }
    var system = master.system
    if booru, let extra = master.booruSystem { system += "\n\n" + extra }
    return Brief(system: system, prompt: request(description: description, terms: terms))
  }
}
