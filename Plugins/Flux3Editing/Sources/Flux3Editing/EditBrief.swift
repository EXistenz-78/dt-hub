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
    var elementParts: [EditPart] = []
    for element in document.elements {
      let desc = element.desc.trimmingCharacters(in: .whitespacesAndNewlines)
      if !desc.isEmpty { elementParts.append(EditPart(kind: .element(id: element.id), text: desc)) }
    }
    let prose = document.prose.trimmingCharacters(in: .whitespacesAndNewlines)
    // The starting sentence alone is not a text to rewrite; with descriptions to write it goes along, so the LLM completes it.
    let bareStart = prose == EditDocument.defaultProse.trimmingCharacters(in: .whitespacesAndNewlines)
    if prose.isEmpty || (bareStart && elementParts.isEmpty) { return elementParts }
    return [EditPart(kind: .prose, text: prose)] + elementParts
  }

  /// Che cosa è ogni elemento, per le parti che si riscrivono: serve all'LLM a scrivere la descrizione giusta (conservare il
  /// disegno solo di ciò che viene da un riferimento). Sta prima dei blocchi: il parser delle risposte lo ignora.
  static func context(for parts: [EditPart], in document: EditDocument, refs: [RefImage]) -> [String] {
    let start = "<ref_image_\(RefNumbering.startImageNumber)>"
    return parts.compactMap { part in
      guard case .element(let id) = part.kind, let element = document.element(id) else { return nil }
      switch element.kind {
      case .fromReference:
        let source = element.refFile.flatMap { RefNumbering.number(ofFile: $0, in: refs) }.map { "<ref_image_\($0)>" } ?? "a Moodboard picture"
        return "\(id): an object taken from \(source)"
      case .new: return "\(id): a new object to describe in rich visual detail"
      case .existing: return "\(id): already in \(start); kept in place, or changed as its description says"
      case .move: return "\(id): already in \(start); moved to another place"
      case .remove: return "\(id): already in \(start); removed"
      }
    }
  }

  /// Il contesto (se c'è), i blocchi e, in fondo, la forma della risposta (con la forma davanti un modello piccolo li riempie tutti).
  static func message(
    _ parts: [EditPart], context: [String] = [], attachments: [EditAttachment] = [], reminder: String? = nil
  ) -> String {
    var text = context.isEmpty ? "" : "Context (what each element is; do not rewrite or repeat it):\n" + context.map { "- " + $0 }.joined(separator: "\n") + "\n\n"
    if !attachments.isEmpty {
      text += "Attached pictures, in order (each is a crop of the object that element takes from a reference picture; use them to describe it accurately, never mention them):\n"
      text += attachments.enumerated().map { "- picture \($0.offset + 1): \($0.element.elementID)" }.joined(separator: "\n") + "\n\n"
    }
    text += parts.map { "## \($0.kind.title)\n\($0.text)" }.joined(separator: "\n\n")
    if let reminder { text += "\n\n" + reminder }
    text += "\n\nReply in English, in exactly this shape, replacing the dots with the English text:\n"
    text += parts.map { "## \($0.kind.title)\n..." }.joined(separator: "\n\n")
    return text
  }
}
