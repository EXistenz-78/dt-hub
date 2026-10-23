import Foundation

/// La risposta dell'LLM: toglie `<think>…</think>` e le recinzioni, poi cerca i titoli richiesti (`## summary`, `## meta`,
/// `## element N (tipo)`, `## tags N`), senza badare alle maiuscole né all'etichetta tra parentesi.
enum MossAnswerParser {
  static func parse(_ answer: String, requested: [MossPart.Kind]) -> [MossPart.Kind: String] {
    let cleaned = clean(answer)
    var lines = cleaned.components(separatedBy: .newlines)
    var segments: [(kind: MossPart.Kind?, lines: [String])] = []
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
    // Senza titoli e con una sola parte richiesta vale tutto il testo.
    if segments.isEmpty, requested.count == 1 {
      lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      let text = tidy(lines.joined(separator: " "))
      return text.isEmpty ? [:] : [requested[0]: text]
    }
    var result: [MossPart.Kind: String] = [:]
    for (position, segment) in segments.enumerated() {
      var text = tidy(segment.lines.joined(separator: " "))
      // L'ultimo blocco di prosa di una risposta troncata finisce a metà frase: non vale (le liste di tag non hanno punto finale).
      if position == segments.count - 1, !text.isEmpty, segment.kind.map(isProse) ?? false, !endsComplete(text) { text = "" }
      if let kind = segment.kind, !text.isEmpty, result[kind] == nil { result[kind] = text }
    }
    return result
  }

  private static func isProse(_ kind: MossPart.Kind) -> Bool {
    switch kind {
    case .summary, .item: return true
    case .meta, .tags: return false
    }
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

  /// Il numero dopo `element` o `tags` (`element 2 (text)`, `element:2`, `Tags 2`).
  private static func number(after word: String, in text: String) -> Int? {
    let rest = text.dropFirst(word.count).drop { $0 == ":" || $0 == " " }
    return Int(rest.prefix { $0.isNumber })
  }

  private static func title(of line: String, requested: [MossPart.Kind]) -> MossPart.Kind? {
    var text = line.trimmingCharacters(in: .whitespaces)
    guard text.hasPrefix("#") else { return nil }
    text = String(text.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
    let lower = text.lowercased()
    if lower == "summary", requested.contains(.summary) { return .summary }
    if lower == "meta", requested.contains(.meta) { return .meta }
    if lower.hasPrefix("element"), let id = number(after: "element", in: lower) {
      return requested.first { if case .item(let other, _) = $0 { return other == id } else { return false } }
    }
    if lower.hasPrefix("tags"), let id = number(after: "tags", in: lower) {
      return requested.first { $0 == .tags(id: id) }
    }
    return nil
  }

  private static func isOtherTitle(_ line: String) -> Bool {
    let text = line.trimmingCharacters(in: .whitespaces)
    guard text.hasPrefix("##") else { return false }
    let lower = String(text.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
    return lower == "summary" || lower == "meta" || lower.hasPrefix("element") || lower.hasPrefix("tags")
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
