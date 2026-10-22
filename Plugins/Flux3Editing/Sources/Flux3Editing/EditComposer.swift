import Foundation

/// Che cosa impedisce «Invia» (spec §6).
enum EditProblem: Equatable, Sendable {
  case noStartImage, noElements, emptyID
  case emptyDescription(String), repeatedID(String), imageMissing(String)
}

/// Un avviso che non blocca.
enum EditWarning: Equatable, Sendable {
  case idNotInProse(String), unknownReferenceInProse(Int), tooManyImages
}

/// Da documento a testo (spec §6): la prosa dell'utente, una riga vuota, l'array JSON. Funzione pura.
enum EditComposer {
  /// FLUX.3 legge al massimo dieci immagini: l'immagine di partenza e nove del Moodboard.
  static let maxReferences = 9

  static func text(_ doc: EditDocument, refs: [RefImage]) -> String {
    let objects = doc.elements.filter { !isMissing($0, refs: refs) }.map { object(of: $0, refs: refs) }
    let array = objects.isEmpty ? "[]" : "[\n" + objects.joined(separator: ",\n") + "\n]"
    let prose = doc.prose.trimmingCharacters(in: .whitespacesAndNewlines)
    return prose.isEmpty ? array : prose + "\n\n" + array
  }

  /// Un elemento «da riferimento» la cui immagine non è più nel Moodboard.
  static func isMissing(_ element: EditElement, refs: [RefImage]) -> Bool {
    guard element.kind == .fromReference else { return false }
    return element.refFile.flatMap { RefNumbering.number(ofFile: $0, in: refs) } == nil
  }

  private static func object(of element: EditElement, refs: [RefImage]) -> String {
    let from: String?
    var source = element.src, target = element.tgt
    switch element.kind {
    case .fromReference:
      from = "ref_image_\(element.refFile.flatMap { RefNumbering.number(ofFile: $0, in: refs) } ?? 0)"
    case .new:
      from = nil
      source = nil
    case .existing:
      from = "ref_image_\(RefNumbering.startImageNumber)"
      target = source
    case .move:
      from = "ref_image_\(RefNumbering.startImageNumber)"
    case .remove:
      from = "ref_image_\(RefNumbering.startImageNumber)"
      target = nil
    }
    let lines = [
      "    \"id\": \(quoted(element.id))",
      "    \"from\": \(from.map(quoted) ?? "null")",
      "    \"src_bbox\": \(source.map(array) ?? "null")",
      "    \"tgt_bbox\": \(target.map(array) ?? "null")",
      "    \"desc\": \(quoted(element.desc))",
    ]
    return "  {\n" + lines.joined(separator: ",\n") + "\n  }"
  }

  private static func array(_ box: BBox) -> String { "[\(box.y0), \(box.x0), \(box.y1), \(box.x1)]" }

  private static func quoted(_ text: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return (try? encoder.encode(text)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
  }

  // MARK: Regole di Invia

  static func problems(_ doc: EditDocument, refs: [RefImage], hasStartImage: Bool) -> [EditProblem] {
    var problems: [EditProblem] = []
    if !hasStartImage { problems.append(.noStartImage) }
    if doc.elements.isEmpty { problems.append(.noElements) }
    for element in doc.elements {
      if element.id.trimmingCharacters(in: .whitespaces).isEmpty { problems.append(.emptyID) }
      let needsDescription = element.kind == .fromReference || element.kind == .new || element.kind == .existing
      if needsDescription, element.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        problems.append(.emptyDescription(element.id))
      }
      if isMissing(element, refs: refs) { problems.append(.imageMissing(element.id)) }
    }
    var reported = Set<String>()
    for element in doc.elements where doc.repeatedIDs.contains(element.id) && reported.insert(element.id).inserted {
      problems.append(.repeatedID(element.id))
    }
    return problems
  }

  static func warnings(_ doc: EditDocument, refs: [RefImage]) -> [EditWarning] {
    var warnings: [EditWarning] = []
    for element in doc.elements where !element.id.isEmpty && !doc.prose.contains("<\(element.id)>") {
      warnings.append(.idNotInProse(element.id))
    }
    let known = Set(refs.map(\.number))
    var unknown = Set<Int>()
    if let pattern = try? NSRegularExpression(pattern: "<ref_image_(\\d+)>") {
      let range = NSRange(doc.prose.startIndex..., in: doc.prose)
      for match in pattern.matches(in: doc.prose, range: range) {
        if let r = Range(match.range(at: 1), in: doc.prose), let n = Int(doc.prose[r]), n > RefNumbering.startImageNumber, !known.contains(n) {
          unknown.insert(n)
        }
      }
    }
    for n in unknown.sorted() { warnings.append(.unknownReferenceInProse(n)) }
    if refs.count > maxReferences { warnings.append(.tooManyImages) }
    return warnings
  }
}
