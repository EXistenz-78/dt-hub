import Foundation

/// Una parte da riscrivere: titolo e testo dell'utente (e, per il Summary, le voci scelte come righe `Categoria: voce`).
struct MossPart: Equatable, Sendable {
  enum Kind: Hashable, Sendable {
    case summary
    case meta
    case item(id: Int, label: MossLabel)
    case tags(id: Int)

    /// Il titolo nel messaggio e nella risposta.
    var title: String {
      switch self {
      case .summary: return "summary"
      case .meta: return "meta"
      case .item(let id, let label): return "element \(id) (\(label.rawValue))"
      case .tags(let id): return "tags \(id)"
      }
    }
  }

  var kind: Kind
  var text: String
  var terms: [String] = []

  var block: String { ([text] + terms).filter { !$0.isEmpty }.joined(separator: "\n") }
}

/// Il messaggio all'LLM (spec §7): blocchi Markdown con un titolo ciascuno. Mai il `text` degli elementi Testo, né
/// posizioni o colori.
enum MossBrief {
  static func parts(from document: MossDocument, catalog: MossCatalog) -> [MossPart] {
    var parts: [MossPart] = []
    let description = document.description.trimmingCharacters(in: .whitespacesAndNewlines)
    let lines = catalog.captionLines(document.selection)
    if !description.isEmpty || !lines.isEmpty { parts.append(MossPart(kind: .summary, text: description, terms: lines)) }
    let meta = document.freeMeta.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    if !meta.isEmpty { parts.append(MossPart(kind: .meta, text: meta.joined(separator: ", "))) }
    for item in document.items {
      let caption = item.caption.trimmingCharacters(in: .whitespacesAndNewlines)
      if !caption.isEmpty { parts.append(MossPart(kind: .item(id: item.id, label: item.label), text: caption)) }
      if !item.tagList.isEmpty { parts.append(MossPart(kind: .tags(id: item.id), text: item.tagList.joined(separator: ", "))) }
    }
    return parts
  }

  /// I blocchi e, in fondo, la forma della risposta (con la forma davanti un modello piccolo li riempie tutti).
  static func message(_ parts: [MossPart], reminder: String? = nil) -> String {
    var text = parts.map { "## \($0.kind.title)\n\($0.block)" }.joined(separator: "\n\n")
    if let reminder { text += "\n\n" + reminder }
    text += "\n\nReply in English, in exactly this shape, replacing the dots with the English text:\n"
    text += parts.map { "## \($0.kind.title)\n..." }.joined(separator: "\n\n")
    return text
  }
}
