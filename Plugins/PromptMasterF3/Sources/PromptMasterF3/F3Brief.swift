import Foundation

/// Una parte da riscrivere: titolo, testo dell'utente e voci scelte (solo per la descrizione).
struct F3Part: Equatable, Sendable {
  enum Kind: Hashable, Sendable {
    case description
    case composition
    case element(id: String)

    /// Il titolo nel messaggio e nella risposta.
    var title: String {
      switch self {
      case .description: return "description"
      case .composition: return "composition"
      case .element(let id): return "element: \(id)"
      }
    }
  }

  var kind: Kind
  var text: String
  /// Righe `Categoria: voce` (categoria in inglese, voce in `en`).
  var terms: [String] = []

  var block: String { ([text] + terms).filter { !$0.isEmpty }.joined(separator: "\n") }
}

/// Il messaggio all'LLM (spec §9): blocchi Markdown con un titolo ciascuno.
enum F3Brief {
  static func parts(from document: F3Document, catalog: F3Catalog) -> [F3Part] {
    var parts: [F3Part] = []
    let description = document.description.trimmingCharacters(in: .whitespacesAndNewlines)
    let lines = catalog.choices(document.selection, mode: document.mode).map { "\($0.category.en): \($0.term.en)" }
    if !description.isEmpty || !lines.isEmpty { parts.append(F3Part(kind: .description, text: description, terms: lines)) }
    let composition = document.composition.trimmingCharacters(in: .whitespacesAndNewlines)
    if !composition.isEmpty { parts.append(F3Part(kind: .composition, text: composition)) }
    for element in document.elements {
      let desc = element.desc.trimmingCharacters(in: .whitespacesAndNewlines)
      if !desc.isEmpty { parts.append(F3Part(kind: .element(id: element.id), text: desc)) }
    }
    return parts
  }

  /// I blocchi e, in fondo, la forma della risposta (con la forma davanti un modello piccolo li riempie tutti).
  static func message(_ parts: [F3Part], reminder: String? = nil) -> String {
    var text = parts.map { "## \($0.kind.title)\n\($0.block)" }.joined(separator: "\n\n")
    if let reminder { text += "\n\n" + reminder }
    text += "\n\nReply in English, in exactly this shape, replacing the dots with the English text:\n"
    text += parts.map { "## \($0.kind.title)\n..." }.joined(separator: "\n\n")
    return text
  }
}
