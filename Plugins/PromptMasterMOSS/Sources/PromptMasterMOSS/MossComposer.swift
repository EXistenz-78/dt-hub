import Foundation

/// Il catalogo come lo vede il composer: le voci scelte, in inglese, divise per destinazione (spec §4, §9).
protocol MossTerms {
  /// Voci di medium e genere (vanno in `summary.meta`).
  func metaTerms(_ selection: Set<String>) -> [String]
  /// Tutte le altre (vanno nella `caption` come frase di termini).
  func captionTerms(_ selection: Set<String>) -> [String]
  /// Le voci scelte del negativo, nell'ordine del catalogo.
  func negativeTerms(_ selection: Set<String>) -> [String]
}

enum MossProblem: Equatable {
  case emptySummary, noItems, unknownSize
  case emptyCaption(item: Int)
  case emptyText(item: Int)
}

/// Dal documento e dalla dimensione al testo che «Invia» scrive nel Prompt (spec §5).
enum MossComposer {
  /// La caption del Summary: il testo libero e, senza LLM, le voci come frase di termini inglesi.
  static func caption(_ document: MossDocument, catalog: some MossTerms) -> String {
    let text = document.description.trimmingCharacters(in: .whitespacesAndNewlines)
    let terms = catalog.captionTerms(document.selection)
    guard !terms.isEmpty else { return text }
    return (text.isEmpty ? "" : text + " ") + terms.joined(separator: ", ") + "."
  }

  static func meta(_ document: MossDocument, catalog: some MossTerms) -> [String] {
    catalog.metaTerms(document.selection)
      + document.freeMeta.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }

  private static func strings(_ list: [String]) -> MossJSON.Value { .array(list.map { .string($0) }) }

  static func json(_ document: MossDocument, catalog: some MossTerms, size: PixelSize) -> String {
    var summary: [(key: String, value: MossJSON.Value)] = []
    let meta = meta(document, catalog: catalog)
    if !meta.isEmpty { summary.append(("meta", strings(meta))) }
    summary.append(("canvas", .string(document.canvas.rawValue)))
    if !document.palette.isEmpty { summary.append(("palette", strings(document.palette))) }
    summary.append(("caption", .string(caption(document, catalog: catalog))))
    let items: [MossJSON.Value] = document.items.map { item in
      var pairs: [(key: String, value: MossJSON.Value)] = [
        ("label", .string(item.label.rawValue)), ("caption", .string(item.caption.trimmingCharacters(in: .whitespacesAndNewlines))),
      ]
      if item.label == .text { pairs.append(("text", .string(item.text))) }
      pairs.append(("bbox", .array(MossGeometry.centered(item.box, in: size).map { .int($0) })))
      if !item.tagList.isEmpty { pairs.append(("tags", strings(item.tagList))) }
      if !item.colors.isEmpty { pairs.append(("palette", strings(item.colors))) }
      return .object(pairs)
    }
    return MossJSON.compact(
      .object([
        ("summary", .object(summary)), ("items", .array(items)),
        ("bbox_coord_space", .string("abs_centralized")), ("bbox_format", .string("yxyx")),
      ]))
  }

  /// Il negativo: le voci scelte (nell'ordine del catalogo), poi il testo libero.
  static func negative(_ document: MossDocument, catalog: some MossTerms) -> String {
    let free = document.negativeText.trimmingCharacters(in: .whitespacesAndNewlines)
    return (catalog.negativeTerms(document.negativeSelection) + (free.isEmpty ? [] : [free])).joined(separator: ", ")
  }

  static func problems(_ document: MossDocument, catalog: some MossTerms, size: PixelSize?) -> [MossProblem] {
    var found: [MossProblem] = []
    if size?.isUsable != true { found.append(.unknownSize) }
    if caption(document, catalog: catalog).isEmpty { found.append(.emptySummary) }
    if document.items.isEmpty { found.append(.noItems) }
    for item in document.items {
      if item.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { found.append(.emptyCaption(item: item.id)) }
      if item.label == .text, item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { found.append(.emptyText(item: item.id)) }
    }
    return found
  }
}
