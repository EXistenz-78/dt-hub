import Foundation

/// I testi prima dell'ultima scrittura dell'LLM, per «Annulla» (spec §7). `restore` arriva con la scrittura (Task 6).
struct MossSnapshot: Codable, Equatable, Sendable {
  var description: String
  var selection: Set<String>
  var freeMeta: [String]
  /// `caption` e `tags` degli elementi, per id.
  var captions: [Int: String]
  var tags: [Int: String]
}

extension MossSnapshot {
  /// I testi di adesso (prima che una scrittura li sostituisca).
  static func take(from document: MossDocument) -> MossSnapshot {
    MossSnapshot(
      description: document.description, selection: document.selection, freeMeta: document.freeMeta,
      captions: Dictionary(document.items.map { ($0.id, $0.caption) }, uniquingKeysWith: { first, _ in first }),
      tags: Dictionary(document.items.map { ($0.id, $0.tags) }, uniquingKeysWith: { first, _ in first }))
  }

  /// Rimette i testi (descrizione, voci, tag liberi, `caption` e tags degli elementi che ci sono ancora) e spegne Annulla.
  func restore(into document: inout MossDocument) {
    document.description = description
    document.selection = selection
    document.freeMeta = freeMeta
    for index in document.items.indices {
      let id = document.items[index].id
      if let caption = captions[id] { document.items[index].caption = caption }
      if let value = tags[id] { document.items[index].tags = value }
    }
    document.snapshot = nil
  }

  /// I testi in Markdown, leggibili a mano (`llm/before.md`).
  var markdown: String {
    var text = "## summary\n\(description)\n\n## selection\n\(selection.sorted().joined(separator: "\n"))\n\n## meta\n\(freeMeta.joined(separator: ", "))"
    for id in captions.keys.sorted() { text += "\n\n## element \(id)\n\(captions[id] ?? "")" }
    for id in tags.keys.sorted() where !(tags[id] ?? "").isEmpty { text += "\n\n## tags \(id)\n\(tags[id] ?? "")" }
    return text + "\n"
  }
}
