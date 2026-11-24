import Foundation

/// La risposta dell'LLM: toglie `<think>…</think>` e le recinzioni, poi cerca i titoli richiesti (`## image_style`,
/// `## ambient_lighting`, `## layer N (tipo)`, `## relation N`), senza badare alle maiuscole né al tipo tra parentesi.
enum MingAnswerParser {
  static func parse(_ answer: String, requested: [MingPart.Kind]) -> [MingPart.Kind: String] {
    let cleaned = clean(answer)
    var lines = cleaned.components(separatedBy: .newlines)
    var segments: [(kind: MingPart.Kind?, lines: [String])] = []
    var current: Int?
    for line in lines {
      if let kind = title(of: line, requested: requested) {
        segments.append((kind, []))
        current = segments.count - 1
      } else if isOtherTitle(line) {
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
    var result: [MingPart.Kind: String] = [:]
    for (position, segment) in segments.enumerated() {
      var text = tidy(segment.lines.joined(separator: " "))
      // L'ultimo blocco di una risposta troncata finisce a metà frase: non vale (stile e luce possono non avere il punto).
      if position == segments.count - 1, !text.isEmpty, segment.kind.map(isSentence) ?? false, !endsComplete(text) { text = "" }
      if let kind = segment.kind, !text.isEmpty, result[kind] == nil { result[kind] = text }
    }
    return result
  }

  private static func isSentence(_ kind: MingPart.Kind) -> Bool {
    switch kind {
    case .layer, .relation: return true
    case .imageStyle, .ambientLighting: return false
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

  private static func number(after word: String, in text: String) -> Int? {
    let rest = text.dropFirst(word.count).drop { $0 == ":" || $0 == " " }
    return Int(rest.prefix { $0.isNumber })
  }

  private static func normalizedTitle(_ line: String) -> String? {
    let text = line.trimmingCharacters(in: .whitespaces)
    guard text.hasPrefix("#") else { return nil }
    return String(text.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
      .replacingOccurrences(of: "*", with: "")
  }

  private static func title(of line: String, requested: [MingPart.Kind]) -> MingPart.Kind? {
    guard let lower = normalizedTitle(line) else { return nil }
    let flat = lower.replacingOccurrences(of: " ", with: "_")
    if flat == "image_style", requested.contains(.imageStyle) { return .imageStyle }
    if flat == "ambient_lighting", requested.contains(.ambientLighting) { return .ambientLighting }
    if lower.hasPrefix("layer"), let id = number(after: "layer", in: lower) {
      return requested.first { if case .layer(let other, _) = $0 { return other == id } else { return false } }
    }
    if lower.hasPrefix("relation"), let id = number(after: "relation", in: lower) {
      return requested.first { $0 == .relation(id: id) }
    }
    return nil
  }

  private static func isOtherTitle(_ line: String) -> Bool {
    guard line.trimmingCharacters(in: .whitespaces).hasPrefix("##"), let lower = normalizedTitle(line) else { return false }
    let flat = lower.replacingOccurrences(of: " ", with: "_")
    return flat == "image_style" || flat == "ambient_lighting" || lower.hasPrefix("layer") || lower.hasPrefix("relation")
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
