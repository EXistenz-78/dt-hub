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
  /// disegno solo di ciò che viene da un riferimento). Con le immagini allegate dice anche in quale immagine sta il suo riquadro.
  /// Sta prima dei blocchi: il parser delle risposte lo ignora.
  static func context(for parts: [EditPart], in document: EditDocument, refs: [RefImage], pictures: [EditPicture] = []) -> [String] {
    let start = "<ref_image_\(RefNumbering.startImageNumber)>"
    // Il numero con cui la legenda chiama un'immagine allegata: la sua posizione nell'elenco, da 1.
    func position(ofNumber number: Int) -> Int? { pictures.firstIndex { $0.number == number }.map { $0 + 1 } }
    let startPosition = pictures.firstIndex { $0.role == .start }.map { $0 + 1 }
    func clause(_ items: [String]) -> String { items.isEmpty ? "" : " (" + items.joined(separator: ", ") + ")" }
    return parts.compactMap { part in
      guard case .element(let id) = part.kind, let element = document.element(id) else { return nil }
      switch element.kind {
      case .fromReference:
        let number = element.refFile.flatMap { RefNumbering.number(ofFile: $0, in: refs) }
        let source = number.map { "<ref_image_\($0)>" } ?? "a Moodboard picture"
        var boxes: [String] = []
        if let number, let place = position(ofNumber: number) { boxes.append("source box in picture \(place)") }
        if let startPosition { boxes.append("destination box in picture \(startPosition)") }
        return "\(id): an object taken from \(source)" + clause(boxes)
      case .new:
        return "\(id): a new object to describe in rich visual detail" + clause(startPosition.map { ["destination box in picture \($0)"] } ?? [])
      case .existing:
        return "\(id): already in \(start); kept in place, or changed as its description says"
          + clause(startPosition.map { ["box in picture \($0)"] } ?? [])
      case .move:
        return "\(id): already in \(start); moved to another place"
          + clause(startPosition.map { ["dashed box = where it is, solid box = where it goes, in picture \($0)"] } ?? [])
      case .remove:
        return "\(id): already in \(start); removed" + clause(startPosition.map { ["dashed box in picture \($0)"] } ?? [])
      }
    }
  }

  /// Il contesto (se c'è), i blocchi e, in fondo, la forma della risposta (con la forma davanti un modello piccolo li riempie tutti).
  static func message(
    _ parts: [EditPart], context: [String] = [], pictures: [EditPicture] = [], reminder: String? = nil
  ) -> String {
    var text = context.isEmpty ? "" : "Context (what each element is; do not rewrite or repeat it):\n" + context.map { "- " + $0 }.joined(separator: "\n") + "\n\n"
    if !pictures.isEmpty {
      text += "Attached pictures, in order (boxes drawn on them, in the colour of each element and labelled with its id, show where the elements are; use them to understand the scene and each element, and never mention the pictures or the boxes in your answer):\n"
      text += pictures.enumerated().map { entry in
        let what = entry.element.role == .start ? "the picture being edited, shown as the canvas of the result" : "a reference picture"
        return "- picture \(entry.offset + 1): <ref_image_\(entry.element.number)>, \(what)"
      }.joined(separator: "\n") + "\n\n"
    }
    text += parts.map { "## \($0.kind.title)\n\($0.text)" }.joined(separator: "\n\n")
    if let reminder { text += "\n\n" + reminder }
    text += "\n\nReply in English, in exactly this shape, replacing the dots with the English text:\n"
    text += parts.map { "## \($0.kind.title)\n..." }.joined(separator: "\n\n")
    return text
  }
}
