import Foundation

/// La fotografia dei testi presa prima di una scrittura dell'LLM (spec §9): serve ad «Annulla». Solo l'ultima.
struct F3Snapshot: Codable, Equatable, Sendable {
  var description: String
  var selection: Set<String>
  var composition: String
  /// La descrizione di ogni elemento, per id.
  var descs: [String: String]
}

extension F3Snapshot {
  /// I testi di adesso (prima che una scrittura li sostituisca).
  static func take(from document: F3Document) -> F3Snapshot {
    F3Snapshot(
      description: document.description, selection: document.selection, composition: document.composition,
      descs: Dictionary(document.elements.map { ($0.id, $0.desc) }, uniquingKeysWith: { first, _ in first }))
  }

  /// Rimette i testi (descrizione, voci, composizione, descrizioni degli elementi che ci sono ancora) e spegne Annulla.
  func restore(into document: inout F3Document) {
    document.description = description
    document.selection = selection
    document.composition = composition
    for index in document.elements.indices {
      if let desc = descs[document.elements[index].id] { document.elements[index].desc = desc }
    }
    document.snapshot = nil
  }

  /// I testi in Markdown, leggibili a mano (`llm/before.md`).
  var markdown: String {
    var text = "## description\n\(description)\n\n## selection\n\(selection.sorted().joined(separator: "\n"))\n\n## composition\n\(composition)"
    for id in descs.keys.sorted() { text += "\n\n## element: \(id)\n\(descs[id] ?? "")" }
    return text + "\n"
  }
}
