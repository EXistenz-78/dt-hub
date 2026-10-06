import Foundation

/// What came back from the language model (spec §7.2): the sentence of each tag that was asked.
enum I4AnswerParser {
  /// The tag in a form that ignores case and writes spaces and dashes as underscores: `<High level description>` is
  /// `high_level_description`.
  static func normalized(_ tag: String) -> String {
    tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      .replacingOccurrences(of: "[\\s-]+", with: "_", options: .regularExpression)
  }

  /// The sentence for each of `tags` that the answer holds (an empty one counts as missing). Reasoning blocks and code
  /// fences go; tags that were not asked and text outside the tags are ignored; a tag that appears twice gives its last
  /// non-empty sentence. When one tag was asked and the answer has no tag-like text at all, the whole answer is the sentence.
  static func parse(_ raw: String, tags: [String]) -> [String: String] {
    let text = withoutFences(withoutThinking(raw))
    let wanted = Set(tags.map(normalized))
    var found: [String: String] = [:]
    let pattern =
      #"<\s*([A-Za-z][A-Za-z0-9_ \-]*?)(?:\s+[A-Za-z_]+\s*=\s*"[^"]*")*\s*>(.*?)<\s*/\s*([A-Za-z][A-Za-z0-9_ \-]*?)\s*>"#
    if let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
      let whole = NSRange(text.startIndex..., in: text)
      for match in expression.matches(in: text, range: whole) {
        guard let open = Range(match.range(at: 1), in: text), let body = Range(match.range(at: 2), in: text),
          let close = Range(match.range(at: 3), in: text)
        else { continue }
        let name = normalized(String(text[open]))
        guard name == normalized(String(text[close])) else { continue }
        guard wanted.contains(name) else { continue }
        let sentence = clean(String(text[body]))
        if !sentence.isEmpty { found[name] = sentence }
      }
    }
    // A bare answer is the sentence only when it has no tag-like text at all: a broken tag is not a sentence.
    let looksTagged = text.range(of: #"<\s*/?\s*[A-Za-z]"#, options: .regularExpression) != nil
    if tags.count == 1, !looksTagged, let only = tags.first {
      let sentence = clean(text)
      if !sentence.isEmpty { found[normalized(only)] = sentence }
    }
    return found
  }

  /// One sentence: no line breaks, no doubled spaces, no quotation marks around all of it.
  static func clean(_ text: String) -> String {
    var result = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    for (open, close) in [("\"", "\""), ("“", "”")] where result.count > 1 && result.hasPrefix(open) && result.hasSuffix(close) {
      let inside = String(result.dropFirst().dropLast())
      if !inside.contains(open) { result = inside.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    return result
  }

  /// Everything up to the last `</think>`; a `<think>` that never closes takes the rest of the text with it.
  private static func withoutThinking(_ text: String) -> String {
    var result = text
    if let close = result.range(of: "</think>", options: .backwards) { result = String(result[close.upperBound...]) }
    if let open = result.range(of: "<think>") { result = String(result[..<open.lowerBound]) }
    return result
  }

  /// The inside of a fenced block (```xml … ```), when the text is one.
  private static func withoutFences(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```"), let firstBreak = trimmed.firstIndex(of: "\n") else { return text }
    var inside = String(trimmed[trimmed.index(after: firstBreak)...])
    if let close = inside.range(of: "```", options: .backwards) { inside = String(inside[..<close.lowerBound]) }
    return inside
  }
}
