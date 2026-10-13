import Foundation

/// The text of a page, made plain (spec §6.3). What is downloaded is data: it is only ever shown as plain text.
enum LAText {
  /// Tags out (scripts and styles with what they hold), entities decoded, white space made single; at most `limit`
  /// characters.
  static func plain(fromHTML html: String, limit: Int = 6000) -> String {
    var text = html.replacingOccurrences(
      of: "<(script|style)[^>]*>.*?</\\1\\s*>", with: " ", options: [.regularExpression, .caseInsensitive])
    text = text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
    text = decodingEntities(text)
    text = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    return String(text.prefix(limit))
  }

  /// A model card without the YAML block it starts with.
  static func withoutFrontMatter(_ markdown: String) -> String {
    guard markdown.hasPrefix("---") else { return markdown }
    let lines = markdown.components(separatedBy: "\n")
    guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
      return markdown
    }
    return lines[(end + 1)...].joined(separator: "\n")
  }

  /// The beginning of a text, cut at the end of a word, with "…" when something is left out.
  static func excerpt(_ text: String, limit: Int = 400) -> String {
    guard text.count > limit else { return text }
    var cut = String(text.prefix(limit))
    if let space = cut.lastIndex(where: \.isWhitespace) { cut = String(cut[..<space]) }
    return cut.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
  }

  /// The first line with something in it.
  static func firstLine(_ text: String) -> String {
    text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
  }

  private static let named: [String: String] = [
    "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "hellip": "…", "mdash": "—", "ndash": "–",
    "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“",
  ]

  private static func decodingEntities(_ text: String) -> String {
    guard text.contains("&"), let pattern = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);") else {
      return text
    }
    var result = ""
    var last = text.startIndex
    for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
      guard let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) else { continue }
      result += text[last..<whole.lowerBound]
      let name = String(text[inner])
      var decoded: String?
      if name.hasPrefix("#x") {
        decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
      } else if name.hasPrefix("#") {
        decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
      } else {
        decoded = named[name.lowercased()]
      }
      result += decoded ?? String(text[whole])
      last = whole.upperBound
    }
    return result + text[last...]
  }
}

/// The names of the LoRAs, for the search on Civitai (spec §6.1).
enum LAName {
  /// What to search for: the LoRA's name, or its file's name made readable when it has none.
  static func query(name: String, file: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    var base = (file as NSString).deletingPathExtension
    // The suffixes Draw Things adds when it converts a LoRA.
    let suffixes = ["_lora", "_f16", "_f8", "_q8p", "_q6p", "_q5p"]
    while let suffix = suffixes.first(where: { base.lowercased().hasSuffix($0) }) { base.removeLast(suffix.count) }
    return base.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
      .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// Letters and digits only, without capitals or accents: what two names are compared by.
  static func key(_ text: String) -> String {
    String(
      text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).unicodeScalars
        .filter { CharacterSet.alphanumerics.contains($0) })
  }

  /// True when the two are the same name, whatever the capitals, the punctuation and a version at the end ("v1.0").
  /// A name that only looks like the other is not a match.
  static func matches(lora: String, result: String) -> Bool {
    let ours = Set([key(lora), key(withoutVersion(lora))]).subtracting([""])
    let theirs = Set([key(result), key(withoutVersion(result))]).subtracting([""])
    return !ours.isDisjoint(with: theirs)
  }

  private static func withoutVersion(_ name: String) -> String {
    name.replacingOccurrences(of: "(^|[\\s_\\-.])[vV][0-9]+(\\.[0-9]+)*\\s*$", with: "", options: .regularExpression)
  }
}
