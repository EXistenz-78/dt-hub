import Foundation

/// The cards of text, their titles and the sentences that make the prompt. Always in English: it is the prompt.
enum Cards {
  static let removeLine = "Remove all the colored marks and keep everything else the same."

  /// The pairs present among the marks, in the order of the first mark of each pair.
  static func keys(of marks: [Mark]) -> [CardKey] {
    var seen: [CardKey] = []
    for mark in marks {
      let key = CardKey(color: mark.color, tool: mark.tool)
      if !seen.contains(key) { seen.append(key) }
    }
    return seen
  }

  static func count(of key: CardKey, in marks: [Mark]) -> Int {
    marks.filter { $0.color == key.color && $0.tool == key.tool }.count
  }

  private static func noun(_ tool: MarkTool, plural: Bool) -> String {
    switch tool {
    case .box: plural ? "boxes" : "box"
    case .circle: plural ? "circles" : "circle"
    case .sketch: plural ? "sketches" : "sketch"
    case .arrow: plural ? "arrows" : "arrow"
    }
  }

  static func title(_ key: CardKey, count: Int) -> String {
    let plural = count > 1
    if key.tool == .arrow {
      return "WHERE \(key.color.rawValue) \(noun(.arrow, plural: plural)) \(plural ? "point" : "points")"
    }
    return "INSIDE \(key.color.rawValue) \(noun(key.tool, plural: plural))"
  }

  /// Blanks and line breaks become one space; nothing is left for an empty text; a full stop is added when there is no end mark.
  static func cleaned(_ text: String) -> String? {
    let joined = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    guard !joined.isEmpty else { return nil }
    return joined.hasSuffix(".") || joined.hasSuffix("!") || joined.hasSuffix("?") ? joined : joined + "."
  }

  static func sentence(_ key: CardKey, count: Int, text: String) -> String? {
    guard let body = cleaned(text) else { return nil }
    let plural = count > 1
    if key.tool == .arrow {
      return "Where the \(key.color.rawValue) \(noun(.arrow, plural: plural)) \(plural ? "point" : "points"): \(body)"
    }
    return "Inside the \(key.color.rawValue) \(noun(key.tool, plural: plural)): \(body)"
  }

  /// The sentences in the order of the cards, then the closing line. Empty when no card has a text (the Prompt field is
  /// then left alone). `texts` is by `CardKey.rawValue`; a text of a pair with no marks is ignored.
  static func prompt(marks: [Mark], texts: [String: String]) -> String {
    let sentences = keys(of: marks).compactMap { key in
      sentence(key, count: count(of: key, in: marks), text: texts[key.rawValue] ?? "")
    }
    return sentences.isEmpty ? "" : (sentences + [removeLine]).joined(separator: " ")
  }
}
