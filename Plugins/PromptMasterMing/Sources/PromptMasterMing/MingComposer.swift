import Foundation

/// Il catalogo come lo vede il composer: le voci scelte, in inglese, divise per destinazione.
protocol MingTerms {
  /// Voci della luce (vanno in `ambient_lighting`).
  func lightingTerms(_ selection: Set<String>) -> [String]
  /// Tutte le altre (vanno in `image_style`).
  func styleTerms(_ selection: Set<String>) -> [String]
}

enum MingProblem: Equatable {
  case unknownSize, noLayers
  case emptyDescription(layer: Int)
  case emptyText(layer: Int)
}

/// Il testo di un livello Testo, a parte il resto: lo stesso nel composer e nell'importatore.
enum MingText {
  static let canonicalPrefix = "A text element reading exactly \""

  /// Le parole esatte e l'aspetto da una descrizione di Ming, solo quando non c'è dubbio (la regola `_detect_text` del nodo
  /// ComfyUI): la forma canonica `A text element reading exactly "…" in …`, oppure un unico `reading exactly "…"`.
  static func detectCanonical(_ description: String) -> (text: String, visual: String)? {
    if description.hasPrefix(canonicalPrefix) {
      let body = String(description.dropFirst(canonicalPrefix.count))
      if let range = body.range(of: "\" in ", options: .backwards) {
        let text = String(body[..<range.lowerBound]), visual = String(body[range.upperBound...])
        if !visual.contains("\""), let last = visual.last, ".!?".contains(last) {
          return (text, last == "." ? String(visual.dropLast()) : visual)
        }
      } else if body.hasSuffix("\".") {
        return (String(body.dropLast(2)), "")
      }
    }
    let pattern = #"\b(?:text(?: element)?|headline|title|caption)?\s*reading exactly "([^"\n]+)""#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
      let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
      let whole = Range(match.range, in: description), let inner = Range(match.range(at: 1), in: description)
    else { return nil }
    let outside = String(description[..<whole.lowerBound]) + String(description[whole.upperBound...])
    guard !outside.contains("\"") else { return nil }
    var visual = outside.trimmingCharacters(in: .whitespaces)
    if ["a", "an"].contains(visual.lowercased()) { visual = "" }
    return (String(description[inner]), visual)
  }

  /// Le parole tra virgolette (dritte o ricurve) di una descrizione.
  static func quotedPhrases(_ text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "\"([^\"\\n]+)\"|“([^”\\n]+)”") else { return [] }
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
      for group in 1...2 { if let r = Range(match.range(at: group), in: text) { return String(text[r]) } }
      return nil
    }
  }

  private static let textWords: Set<String> = [
    "text", "lettering", "letters", "headline", "title", "heading", "subtitle", "tagline", "slogan", "caption", "typography",
    "typeface", "font", "wordmark", "reads", "reading", "says", "button", "label",
  ]

  /// Un livello che mostra un solo testo tra virgolette e parla di lettere (`Bold white headline "SALE" at the top`): le parole
  /// diventano il testo esatto e la descrizione intera resta l'aspetto (si riscrive com'era finché non la si cambia).
  static func detectLoose(_ description: String) -> String? {
    let phrases = quotedPhrases(description)
    guard phrases.count == 1, !phrases[0].trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    let words = Set(description.lowercased().split { !$0.isLetter }.map(String.init))
    return words.isDisjoint(with: textWords) ? nil : phrases[0]
  }

  /// La descrizione di un livello Testo nel JSON. Se il livello viene da un JSON importato e il suo aspetto non è cambiato, si
  /// riscrive la descrizione di allora (con le parole nuove, se sono cambiate); altrimenti la forma canonica del nodo ComfyUI.
  static func description(of layer: MingLayer) -> String {
    let text = layer.text, visual = layer.description.trimmingCharacters(in: .whitespacesAndNewlines)
    if let raw = layer.rawDescription, let imported = layer.importedText, visual == layer.importedVisual?.trimmingCharacters(in: .whitespacesAndNewlines) {
      if text == imported { return raw }
      if let range = raw.range(of: "\"" + imported + "\"") ?? raw.range(of: "“" + imported + "”") {
        return raw.replacingCharacters(in: range, with: "\"" + text + "\"")
      }
    }
    var look = visual
    for form in ["\"\(text)\"", "“\(text)”", text] where !text.isEmpty { look = look.replacingOccurrences(of: form, with: "the specified text") }
    let suffix = look.isEmpty ? "" : " in " + look
    let result = canonicalPrefix + text + "\"" + suffix
    return look.last.map { ".!?".contains($0) } == true ? result : result + "."
  }
}

/// Dal documento e dalla dimensione al JSON che «Invia» scrive nel Prompt.
enum MingComposer {
  private static func joined(_ text: String, _ terms: [String]) -> String {
    var base = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !terms.isEmpty else { return base }
    while let last = base.last, ".,;".contains(last) { base.removeLast() }
    return (base.isEmpty ? "" : base + ", ") + terms.joined(separator: ", ")
  }

  /// `image_style`: il testo e, dopo, le voci scelte (fuori dalla luce).
  static func imageStyle(_ document: MingDocument, catalog: some MingTerms) -> String {
    joined(document.imageStyle, catalog.styleTerms(document.selection))
  }

  static func ambientLighting(_ document: MingDocument, catalog: some MingTerms) -> String {
    joined(document.ambientLighting, catalog.lightingTerms(document.selection))
  }

  static func description(of layer: MingLayer) -> String {
    layer.kind == .text ? MingText.description(of: layer) : layer.description.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// `hierarchy_and_relation`: le parole di un testo non ci vanno (il Family prompt e il nodo le tolgono).
  static func relation(of layer: MingLayer) -> String {
    var relation = layer.relation.trimmingCharacters(in: .whitespacesAndNewlines)
    if layer.kind == .text, !layer.text.isEmpty, relation.contains(layer.text) {
      relation = relation.replacingOccurrences(of: "\"\(layer.text)\"", with: "this text element")
        .replacingOccurrences(of: layer.text, with: "this text element")
    }
    return relation
  }

  static func value(_ document: MingDocument, catalog: some MingTerms, size: PixelSize) -> MingJSON.Value {
    let settings: MingJSON.Value = .object([
      ("aspect_ratio", .string(MingGeometry.aspectRatio(size))),
      ("ambient_lighting", .string(ambientLighting(document, catalog: catalog))),
      ("image_style", .string(imageStyle(document, catalog: catalog))),
    ])
    let layers: [MingJSON.Value] = document.layers.map { layer in
      .object([
        ("description", .string(description(of: layer))), ("coordinates", .string(MingGeometry.coordinates(layer.box))),
        ("hierarchy_and_relation", .string(relation(of: layer))), ("color_specs", .array(layer.colors.map { .string($0) })),
      ])
    }
    return .object([("canvas_settings", settings), ("layers", .array(layers))])
  }

  static func json(_ document: MingDocument, catalog: some MingTerms, size: PixelSize) -> String {
    MingJSON.pretty(value(document, catalog: catalog, size: size))
  }

  static func problems(_ document: MingDocument, size: PixelSize?) -> [MingProblem] {
    var found: [MingProblem] = []
    if size?.isUsable != true { found.append(.unknownSize) }
    if document.layers.isEmpty { found.append(.noLayers) }
    for layer in document.layers {
      switch layer.kind {
      case .object:
        if layer.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { found.append(.emptyDescription(layer: layer.id)) }
      case .text:
        if layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { found.append(.emptyText(layer: layer.id)) }
      }
    }
    return found
  }
}
