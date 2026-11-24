import Foundation

/// Un JSON di Ming letto: le impostazioni della tela, i livelli (dallo sfondo al primo piano) e gli avvisi.
struct MingImported: Equatable, Sendable {
  var imageStyle: String
  var ambientLighting: String
  /// La forma che `aspect_ratio` dice; nil se manca o non si legge.
  var shape: MingGeometry.Shape?
  var layers: [MingLayer]
  var warnings: [String]
}

/// Legge un prompt di Ming (quello del nodo ComfyUI, quello del Family prompt dell'app, quello che scrive un LLM) e lo rende
/// livelli del tab. È più tollerante del nodo dove un errore non cambia il senso (un colore illeggibile si scarta, una chiave
/// in più si ignora), ma rifiuta tutto se manca la struttura: due chiavi, `canvas_settings` e `layers`, e per ogni livello una
/// descrizione e coordinate leggibili. Niente cambia finché tutto il documento non è valido.
enum MingImporter {
  struct Failure: Error, Equatable { var reason: String }

  /// Il JSON dentro un testo: senza recinzioni Markdown né `<think>`, dalla prima `{` all'ultima `}`.
  static func jsonText(in text: String) -> String? {
    var body = text
    if let close = body.range(of: "</think>", options: .caseInsensitive) { body = String(body[close.upperBound...]) }
    guard let first = body.firstIndex(of: "{"), let last = body.lastIndex(of: "}"), first < last else { return nil }
    return String(body[first...last])
  }

  /// Vero se il testo è un prompt di Ming che si può importare (per l'avviso sopra il canvas).
  static func looksImportable(_ text: String) -> Bool {
    (try? parse(text).get()) != nil
  }

  /// Ripara gli errori di battitura più comuni di un JSON scritto a mano o da un LLM, senza toccare il contenuto dei testi:
  /// virgolette tipografiche che aprono o chiudono una stringa, la virgola mancante a fine riga, la virgola in più prima di
  /// `}` o `]`. Le stringhe JSON non vanno a capo, quindi a fine riga una `”` può solo chiudere una stringa.
  static func repaired(_ json: String) -> (text: String, fixes: [String]) {
    var text = json
    var fixes: [String] = []
    func replace(_ pattern: String, _ template: String, _ note: String) {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
      let range = NSRange(text.startIndex..., in: text)
      guard regex.firstMatch(in: text, range: range) != nil else { return }
      text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
      fixes.append(note)
    }
    // Una stringa chiusa da una virgoletta tipografica a fine riga (eventualmente seguita da virgola o parentesi).
    replace(#"[”“″](\s*[,}\]]?\s*)$"#, "\"$1", "a string closed with a typographic quote")
    // Una chiave o un valore aperti da una virgoletta tipografica dopo `{`, `[`, `,`, `:` o a inizio riga.
    replace(#"(^\s*|[{\[,:]\s*)[“”″]"#, "$1\"", "a string opened with a typographic quote")
    // La virgola mancante fra un valore a fine riga e la chiave o il valore della riga dopo.
    replace(#"("|\d|true|false|null|\}|\])([ \t]*)\n(\s*)("|\{|\[)"#, "$1,$2\n$3$4", "a missing comma")
    // La virgola in più prima della chiusura.
    replace(#",(\s*[}\]])"#, "$1", "an extra comma")
    return (text, fixes)
  }

  /// La posizione dell'errore come la dice il lettore JSON («line 4, column 122»), se la dice.
  private static func position(of error: Error) -> String? {
    let text = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? ""
    guard let regex = try? NSRegularExpression(pattern: #"line (\d+), column (\d+)"#),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let line = Range(match.range(at: 1), in: text), let column = Range(match.range(at: 2), in: text)
    else { return nil }
    return "line \(text[line]), column \(text[column])"
  }

  private static func object(from json: String) -> Result<Any, Error> {
    Result { try JSONSerialization.jsonObject(with: Data(json.utf8)) }
  }

  static func parse(_ text: String) -> Result<MingImported, Failure> {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .failure(Failure(reason: "empty")) }
    guard let json = jsonText(in: trimmed) else { return .failure(Failure(reason: "not a JSON object")) }
    var warnings: [String] = []
    let parsed: Any
    switch object(from: json) {
    case .success(let value):
      parsed = value
    case .failure(let error):
      let fix = repaired(json)
      guard !fix.fixes.isEmpty, case .success(let value) = object(from: fix.text) else {
        let place = position(of: error).map { "invalid JSON at \($0)" } ?? "invalid JSON"
        return .failure(Failure(reason: place))
      }
      parsed = value
      warnings.append("The JSON had errors that were fixed: \(fix.fixes.joined(separator: ", ")).")
    }
    guard let document = parsed as? [String: Any] else { return .failure(Failure(reason: "not a JSON object")) }
    guard let settings = document["canvas_settings"] as? [String: Any] else {
      return .failure(Failure(reason: "canvas_settings is missing"))
    }
    guard let layers = document["layers"] as? [Any] else { return .failure(Failure(reason: "layers is missing")) }
    if !Set(document.keys).subtracting(["canvas_settings", "layers"]).isEmpty { warnings.append("Other top-level keys were ignored.") }
    func string(_ value: Any?, _ name: String) -> String {
      if value == nil { return "" }
      if let text = value as? String { return text }
      warnings.append("\(name) is not a string and was left empty.")
      return ""
    }
    let style = string(settings["image_style"], "image_style"), lighting = string(settings["ambient_lighting"], "ambient_lighting")
    let ratio = string(settings["aspect_ratio"], "aspect_ratio")
    let shape = MingGeometry.shape(of: ratio)
    if shape == nil { warnings.append("aspect_ratio is missing or unreadable: the Generation size stays as it is.") }
    var result: [MingLayer] = []
    for (index, value) in layers.enumerated() {
      let label = "Layer \(index + 1)"
      guard let layer = value as? [String: Any] else { return .failure(Failure(reason: "\(label) is not an object")) }
      guard let description = layer["description"] as? String, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .failure(Failure(reason: "\(label) has no description"))
      }
      guard let coordinates = layer["coordinates"] as? String, let box = MingGeometry.parse(coordinates) else {
        return .failure(Failure(reason: "\(label) has no readable coordinates"))
      }
      let relation: String
      if let text = layer["hierarchy_and_relation"] as? String {
        relation = text
      } else {
        relation = ""
        if layer["hierarchy_and_relation"] != nil { warnings.append("\(label): hierarchy_and_relation is not a string and was left empty.") }
      }
      var colors: [String] = []
      for color in layer["color_specs"] as? [Any] ?? [] {
        if let hex = (color as? String).flatMap(Palette.normalize) { colors.append(hex) } else { warnings.append("\(label): a color that is not #RRGGBB was dropped.") }
      }
      var item = MingLayer(
        id: index + 1, kind: .object, description: description, text: "", relation: relation, colors: colors, box: box,
        expanded: false)
      if let found = MingText.detectCanonical(description), !found.text.trimmingCharacters(in: .whitespaces).isEmpty {
        item.kind = .text
        item.text = found.text
        item.description = found.visual
        item.rawDescription = description
        item.importedText = found.text
        item.importedVisual = found.visual
      } else if let words = MingText.detectLoose(description) {
        item.kind = .text
        item.text = words
        item.rawDescription = description
        item.importedText = words
        item.importedVisual = description
      }
      result.append(item)
    }
    if result.isEmpty { warnings.append("The JSON has no layers.") }
    return .success(MingImported(imageStyle: style, ambientLighting: lighting, shape: shape, layers: result, warnings: warnings))
  }
}
