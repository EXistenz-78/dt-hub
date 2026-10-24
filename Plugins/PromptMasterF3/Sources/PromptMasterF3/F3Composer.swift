import Foundation

/// Un elemento della scena: nasce da un `<id>` nel testo della composizione (spec §7).
struct F3Element: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var desc: String
  var box: BBox
  /// Il colore (indice nella tavolozza di otto): assegnato alla nascita, mai cambiato.
  var colorIndex: Int
  var expanded: Bool
}

enum F3Problem: Equatable, Sendable {
  case noElements
  case emptyDescription(id: String)
  case duplicateID(String)
}

/// Il testo che «Invia» manda nel Prompt (spec §5): descrizione, composizione, array JSON dei riquadri.
enum F3Composer {
  static func text(description: String, terms: [String], composition: String, elements: [F3Element]) -> String {
    [firstBlock(description: description, terms: terms), composition.trimmingCharacters(in: .whitespacesAndNewlines), jsonArray(elements)]
      .joined(separator: "\n\n")
  }

  /// Il testo prima dell'array: la descrizione con la frase delle voci, e la composizione. È l'«ORIGINAL PROMPT» che va al PUP.
  static func prose(description: String, terms: [String], composition: String) -> String {
    [firstBlock(description: description, terms: terms), composition.trimmingCharacters(in: .whitespacesAndNewlines)]
      .filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  private static func firstBlock(description: String, terms: [String]) -> String {
    var first = description.trimmingCharacters(in: .whitespacesAndNewlines)
    if !terms.isEmpty {
      let sentence = terms.joined(separator: ", ") + "."
      first = first.isEmpty ? sentence : first + " " + sentence
    }
    return first
  }

  /// `[ {id, bbox, desc} ]` indentato di due spazi, nell'ordine delle schede.
  static func jsonArray(_ elements: [F3Element]) -> String {
    guard !elements.isEmpty else { return "[]" }
    let items = elements.map { element in
      let numbers = [element.box.y0, element.box.x0, element.box.y1, element.box.x1].map(String.init).joined(separator: ", ")
      return "  {\n    \"id\": \(quoted(element.id)),\n    \"bbox\": [\(numbers)],\n    \"desc\": \(quoted(element.desc))\n  }"
    }
    return "[\n" + items.joined(separator: ",\n") + "\n]"
  }

  static func problems(composition: String, elements: [F3Element]) -> [F3Problem] {
    if elements.isEmpty { return [.noElements] }
    var result: [F3Problem] = []
    var seen = Set<String>()
    var reported = Set<String>()
    for element in elements {
      if element.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.emptyDescription(id: element.id)) }
      if !seen.insert(element.id).inserted, reported.insert(element.id).inserted { result.append(.duplicateID(element.id)) }
    }
    return result
  }

  /// Una stringa come la scrive JSON (virgolette, barre, a capo escapati; l'emoji resta com'è).
  private static func quoted(_ text: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    guard let data = try? encoder.encode(text), let out = String(data: data, encoding: .utf8) else { return "\"\"" }
    return out
  }
}
