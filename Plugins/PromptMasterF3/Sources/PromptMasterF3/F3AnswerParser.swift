import Foundation

/// La risposta dell'LLM: toglie `<think>…</think>` e le recinzioni, poi cerca i titoli richiesti (`## description`,
/// `## composition`, `## element: <id>`), senza badare alle maiuscole.
enum F3AnswerParser {
  static func parse(_ answer: String, requested: [F3Part.Kind]) -> [F3Part.Kind: String] {
    let cleaned = clean(answer)
    var lines = cleaned.components(separatedBy: .newlines)
    // Senza titoli e con una sola parte richiesta vale tutto il testo.
    var segments: [(kind: F3Part.Kind?, lines: [String])] = []
    var current: Int?
    for line in lines {
      if let kind = title(of: line, requested: requested) {
        segments.append((kind, []))
        current = segments.count - 1
      } else if isOtherTitle(line) {
        // Un titolo non richiesto chiude il blocco di prima e il suo testo non vale.
        segments.append((nil, []))
        current = segments.count - 1
      } else if let index = current {
        segments[index].lines.append(line)
      }
    }
    if segments.isEmpty, requested.count == 1 {
      lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      let text = tidy(lines.joined(separator: " "))
      return text.isEmpty ? [:] : [requested[0]: text]
    }
    var result: [F3Part.Kind: String] = [:]
    for (position, segment) in segments.enumerated() {
      var text = tidy(segment.lines.joined(separator: " "))
      // L'ultimo blocco di una risposta troncata finisce a metà frase: non vale.
      if position == segments.count - 1, !text.isEmpty, !endsComplete(text) { text = "" }
      if let kind = segment.kind, !text.isEmpty, result[kind] == nil { result[kind] = text }
    }
    return result
  }

  static func clean(_ answer: String) -> String {
    var text = answer
    while let open = text.range(of: "<think>", options: .caseInsensitive) {
      if let close = text.range(of: "</think>", options: .caseInsensitive, range: open.upperBound..<text.endIndex) {
        text.removeSubrange(open.lowerBound..<close.upperBound)
      } else {
        text.removeSubrange(open.lowerBound..<text.endIndex)
      }
    }
    if let close = text.range(of: "</think>", options: .caseInsensitive) { text.removeSubrange(text.startIndex..<close.upperBound) }
    return text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
      .joined(separator: "\n")
  }

  private static func title(of line: String, requested: [F3Part.Kind]) -> F3Part.Kind? {
    var text = line.trimmingCharacters(in: .whitespaces)
    guard text.hasPrefix("#") else { return nil }
    text = String(text.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
    let lower = text.lowercased()
    if lower == "description", requested.contains(.description) { return .description }
    if lower == "composition", requested.contains(.composition) { return .composition }
    guard lower.hasPrefix("element") else { return nil }
    let rest = text.dropFirst("element".count).drop { $0 == ":" || $0 == " " }
    let id = String(rest).trimmingCharacters(in: .whitespaces)
    if let found = requested.first(where: { $0 == .element(id: id) }) { return found }
    return requested.first { kind in
      if case .element(let other) = kind { return other.lowercased() == id.lowercased() }
      return false
    }
  }

  private static func isOtherTitle(_ line: String) -> Bool {
    let text = line.trimmingCharacters(in: .whitespaces)
    guard text.hasPrefix("##") else { return false }
    let lower = String(text.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
    return lower == "description" || lower == "composition" || lower.hasPrefix("element")
  }

  private static func tidy(_ text: String) -> String {
    var result = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    if result.count >= 2, let first = result.first, let last = result.last, (first == "\"" && last == "\"") || (first == "“" && last == "”") {
      result = String(result.dropFirst().dropLast())
    }
    return result.trimmingCharacters(in: .whitespaces)
  }

  private static func endsComplete(_ text: String) -> Bool {
    guard let last = text.last else { return false }
    return ".!?…\"”)>»".contains(last)
  }
}
