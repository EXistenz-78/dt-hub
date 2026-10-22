import Foundation

/// Una parte da riscrivere: la prosa o la descrizione di un elemento.
struct EditPart: Equatable, Sendable {
  enum Kind: Hashable, Sendable {
    case prose
    case element(id: String)

    /// Il titolo nel messaggio e nella risposta.
    var title: String {
      switch self {
      case .prose: return "prose"
      case .element(let id): return "element: \(id)"
      }
    }
  }

  var kind: Kind
  var text: String
}

/// Il messaggio all'LLM (spec §7): blocchi Markdown con un titolo ciascuno.
enum EditBrief {
  static func parts(from document: EditDocument) -> [EditPart] {
    var parts: [EditPart] = []
    let prose = document.prose.trimmingCharacters(in: .whitespacesAndNewlines)
    if !prose.isEmpty { parts.append(EditPart(kind: .prose, text: prose)) }
    for element in document.elements {
      let desc = element.desc.trimmingCharacters(in: .whitespacesAndNewlines)
      if !desc.isEmpty { parts.append(EditPart(kind: .element(id: element.id), text: desc)) }
    }
    return parts
  }

  /// I blocchi e, in fondo, la forma della risposta (con la forma davanti un modello piccolo li riempie tutti).
  static func message(_ parts: [EditPart], reminder: String? = nil) -> String {
    var text = parts.map { "## \($0.kind.title)\n\($0.text)" }.joined(separator: "\n\n")
    if let reminder { text += "\n\n" + reminder }
    text += "\n\nReply in English, in exactly this shape, replacing the dots with the English text:\n"
    text += parts.map { "## \($0.kind.title)\n..." }.joined(separator: "\n\n")
    return text
  }
}
