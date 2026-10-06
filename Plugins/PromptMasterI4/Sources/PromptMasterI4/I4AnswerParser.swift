import Foundation

/// What came back from the language model (spec §7.2): the sentence of each tag that was asked.
enum I4AnswerParser {
  /// The most characters of an answer that are read.
  static let maxLength = 100_000

  /// The tag in a form that ignores case and writes spaces and dashes as underscores: `<High level description>` is
  /// `high_level_description`.
  static func normalized(_ tag: String) -> String {
    tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      .replacingOccurrences(of: "[\\s-]+", with: "_", options: .regularExpression)
  }

  /// The sentence for each of `tags` that the answer holds (an empty one counts as missing). Reasoning blocks and code
  /// fences go; tags that were not asked and text outside the tags are ignored; each opening tag takes the first closing tag
  /// of the same name after it (none, and it is missing); a tag that appears twice gives its last non-empty sentence. When
  /// one tag was asked and the answer has no tag-like text at all, the whole answer is the sentence.
  ///
  /// The opening and the closing tags are found in one pass each and matched by name, so the time is that of reading the
  /// text, whatever the model wrote: a search from every opening tag to the end would be quadratic on a model that loops.
  static func parse(_ raw: String, tags: [String]) -> [String: String] {
    // An answer is at most a few thousand tokens; anything longer is a model gone astray, and only its start is read.
    let text = withoutFences(withoutThinking(String(raw.prefix(maxLength))))
    let wanted = Set(tags.map(normalized))
    var found: [String: String] = [:]

    // A tag name may have single spaces between words (`<High level description>`), never a run of them.
    let name = #"[A-Za-z][A-Za-z0-9_\-]*(?: [A-Za-z0-9_\-]+)*"#
    let attributes = #"(?:\s+[A-Za-z_]+\s*=\s*"[^"]*")*"#
    if let opening = try? NSRegularExpression(pattern: #"<[ \t]*(\#(name))\#(attributes)\s*>"#, options: .caseInsensitive),
      let closing = try? NSRegularExpression(pattern: #"<[ \t]*/[ \t]*(\#(name))[ \t]*>"#, options: .caseInsensitive)
    {
      let whole = NSRange(text.startIndex..., in: text)
      let nsText = text as NSString
      var closes: [String: [NSRange]] = [:]  // by name, in the order of the text
      for match in closing.matches(in: text, range: whole) {
        closes[normalized(nsText.substring(with: match.range(at: 1))), default: []].append(match.range)
      }
      for match in opening.matches(in: text, range: whole) {
        let tag = normalized(nsText.substring(with: match.range(at: 1)))
        guard wanted.contains(tag), let candidates = closes[tag] else { continue }
        // The first closing tag that starts at or after the end of this opening one (binary search).
        let start = match.range.location + match.range.length
        var low = 0, high = candidates.count
        while low < high {
          let middle = (low + high) / 2
          if candidates[middle].location < start { low = middle + 1 } else { high = middle }
        }
        guard low < candidates.count else { continue }
        let body = nsText.substring(with: NSRange(location: start, length: candidates[low].location - start))
        let sentence = clean(body)
        if !sentence.isEmpty { found[tag] = sentence }
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

  /// One sentence: no line breaks, no doubled spaces, no quotation marks around all of it. Nothing but dots is not a
  /// sentence: it is the shape of the reply, copied.
  static func clean(_ text: String) -> String {
    let result = tidy(text)
    return result.allSatisfy({ $0 == "." || $0 == "…" || $0.isWhitespace }) ? "" : result
  }

  private static func tidy(_ text: String) -> String {
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
