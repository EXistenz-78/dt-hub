import Foundation

/// What is sent to the language model: the system prompt and the request.
struct Brief: Equatable {
  var system: String
  var prompt: String
}

enum BriefBuilder {
  /// The terms grouped by their category, in the order of the list (the terms of one category are next to each other).
  private static func grouped(_ terms: [SelectedTerm]) -> [(label: String, items: [String])] {
    var result: [(label: String, items: [String])] = []
    for term in terms {
      if let last = result.last, last.label == term.categoryEnglish {
        result[result.count - 1].items.append(term.english)
      } else {
        result.append((term.categoryEnglish, [term.english]))
      }
    }
    return result
  }

  /// One line for each category, `- Light Source: Starlight`. The category says how a term is to be used: without it a
  /// language model may take «butterfly lighting» for butterflies.
  private static func lines(_ terms: [SelectedTerm]) -> [String] {
    grouped(terms).map { $0.label.isEmpty ? "- \($0.items.joined(separator: ", "))" : "- \($0.label): \($0.items.joined(separator: ", "))" }
  }

  /// The request: the description as the user wrote it (any language), then the terms in English with their category,
  /// those to include and those to avoid.
  static func request(description: String, terms: [SelectedTerm]) -> String {
    let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
    var lines = ["Description (any language):", text.isEmpty ? "(none: build the image from the terms alone)" : text]
    let include = terms.filter { !$0.isNegative }
    let avoid = terms.filter(\.isNegative)
    if !include.isEmpty { lines += ["", "Terms to include:"] + Self.lines(include) }
    if !avoid.isEmpty { lines += ["", "Terms to avoid:"] + Self.lines(avoid) }
    return lines.joined(separator: "\n")
  }

  /// The request for Qwen's prompt enhancer, which expects the user's own words: the description, then one
  /// line, `Look: light source: Starlight; color palette: Jewel tones.` It has no negative prompt, so the terms to avoid
  /// stay out.
  static func enhancerRequest(description: String, terms: [SelectedTerm]) -> String {
    let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
    let groups = grouped(terms.filter { !$0.isNegative })
    let look = groups.map { $0.label.isEmpty ? $0.items.joined(separator: ", ") : "\($0.label.lowercased()): \($0.items.joined(separator: ", "))" }
    guard !look.isEmpty else { return text }
    let line = "Look: " + look.joined(separator: "; ") + "."
    return text.isEmpty ? line : text + "\n\n" + line
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
