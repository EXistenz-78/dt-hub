import Foundation

/// What the language model answered, cleaned up.
struct ParsedAnswer: Equatable {
  var prompt: String
  var negative: String?
  /// The aspect ratio a prompt enhancer suggests ("3:2").
  var ratio: String?
}

enum AnswerParser {
  /// The prompt (and the negative prompt, and the ratio) in an answer. Reasoning blocks (`<think>…</think>`) and code
  /// fences go; a JSON object gives its `prompt` (or `rewritten_prompt`, or `positive_prompt`) and `negative`; anything
  /// else, a malformed JSON included, is taken as the prompt itself. Nil when nothing is left.
  static func parse(_ raw: String) -> ParsedAnswer? {
    var text = withoutThinking(raw)
    text = withoutFences(text).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
      let object = (try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8))) as? [String: Any],
      let prompt = ["prompt", "rewritten_prompt", "positive_prompt"].lazy.compactMap({ clean(object[$0]) }).first
    {
      return ParsedAnswer(
        prompt: prompt, negative: ["negative", "negative_prompt"].lazy.compactMap { clean(object[$0]) }.first,
        ratio: clean(object["wh_ratio"]))
    }
    return ParsedAnswer(prompt: unquoted(text))
  }

  private static func clean(_ value: Any?) -> String? {
    guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
    return text
  }

  /// Everything up to the last `</think>`; a `<think>` that never closes takes the rest of the text with it.
  private static func withoutThinking(_ text: String) -> String {
    var result = text
    if let close = result.range(of: "</think>", options: .backwards) { result = String(result[close.upperBound...]) }
    if let open = result.range(of: "<think>") { result = String(result[..<open.lowerBound]) }
    return result
  }

  /// The inside of a fenced block (```json … ```), when the text is one.
  private static func withoutFences(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```"), let firstBreak = trimmed.firstIndex(of: "\n") else { return text }
    var inside = String(trimmed[trimmed.index(after: firstBreak)...])
    if let close = inside.range(of: "```", options: .backwards) { inside = String(inside[..<close.lowerBound]) }
    return inside
  }

  /// A prompt wrapped in one pair of quotation marks loses them.
  private static func unquoted(_ text: String) -> String {
    for (open, close) in [("\"", "\""), ("“", "”")] where text.count > 1 && text.hasPrefix(open) && text.hasSuffix(close) {
      let inside = String(text.dropFirst().dropLast())
      if !inside.contains(open) { return inside.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    return text
  }
}
