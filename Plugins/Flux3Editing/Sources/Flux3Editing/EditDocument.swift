import Foundation

/// Il testo di una scrittura dell'LLM prima che avvenisse, per «Annulla» (solo l'ultima).
struct EditSnapshot: Codable, Equatable, Sendable {
  var prose: String
  /// La `desc` di ogni elemento, per id.
  var descriptions: [String: String]
}

/// Quello che l'utente ha scritto e disegnato (spec §5, §8).
struct EditDocument: Codable, Equatable, Sendable {
  var prose = ""
  var elements: [EditElement] = []
  var snapshot: EditSnapshot?
  /// Quale immagine del Moodboard mostra la prima tela (0 = la prima accesa).
  var referenceIndex = 0

  static let maxTargetSide = 300
  static let targetGap = 20

  // MARK: Disegnare

  /// Un riquadro disegnato sull'immagine `file` del Moodboard: nasce la coppia, con la destinazione al centro del canvas
  /// (stessa proporzione dell'origine, lato massimo il 30% della griglia).
  mutating func draw(onReference file: String, box: BBox) {
    let width = box.x1 - box.x0, height = box.y1 - box.y0
    let scale = min(1, Double(Self.maxTargetSide) / Double(max(width, height, 1)))
    let (tw, th) = (max(BBox.minSide, Int((Double(width) * scale).rounded())), max(BBox.minSide, Int((Double(height) * scale).rounded())))
    let (x0, y0) = (BBox.grid / 2 - tw / 2, BBox.grid / 2 - th / 2)
    let target = BBox(y0: y0, x0: x0, y1: y0 + th, x1: x0 + tw)
    elements.append(
      EditElement(
        id: freeID(), colorIndex: nextColor, kind: .fromReference, refFile: file, src: box, tgt: target, desc: ""))
  }

  /// Un riquadro disegnato sull'immagine di partenza: un elemento nuovo, senza controparte.
  mutating func draw(onCanvas box: BBox) {
    elements.append(EditElement(id: freeID(), colorIndex: nextColor, kind: .new, refFile: nil, src: nil, tgt: box, desc: ""))
  }

  private var nextColor: Int { (elements.map(\.colorIndex).max() ?? -1) + 1 }

  private func freeID() -> String {
    var number = 1
    while elements.contains(where: { $0.id == "el_\(number)" }) { number += 1 }
    return "el_\(number)"
  }

  // MARK: Cambiare tipo

  /// Cambia il tipo di un elemento senza perdere il riquadro (spec §5). Una coppia «da riferimento» non cambia tipo.
  mutating func setKind(_ kind: EditKind, of id: String) {
    guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
    var element = elements[index]
    guard element.kind != .fromReference, kind != .fromReference, element.kind != kind else { return }
    // Il riquadro «corrente»: la destinazione se c'è (new, move), altrimenti l'origine.
    let current = element.tgt ?? element.src
    switch kind {
    case .new:
      element.tgt = current
      element.src = nil
    case .existing:
      // Sposta → Esistente tiene la destinazione; gli altri tengono il loro unico riquadro.
      element.src = current
      element.tgt = nil
    case .remove:
      // Sposta → Togli tiene l'origine; New → Togli il riquadro che c'è.
      element.src = element.kind == .move ? element.src : current
      element.tgt = nil
    case .move:
      let source = current
      element.src = source
      element.tgt = source.map(Self.beside)
    case .fromReference:
      return
    }
    element.kind = kind
    elements[index] = element
  }

  /// La destinazione di «Sposta» al suo nascere: accanto all'origine (a destra se c'è posto, altrimenti a sinistra).
  static func beside(_ box: BBox) -> BBox {
    let width = box.x1 - box.x0
    var x0 = box.x0 + width + targetGap
    if x0 + width > BBox.grid { x0 = box.x0 - width - targetGap }
    x0 = min(max(x0, 0), BBox.grid - width)
    return BBox(y0: box.y0, x0: x0, y1: box.y1, x1: x0 + width)
  }

  // MARK: Elenco

  mutating func delete(_ id: String) { elements.removeAll { $0.id == id } }

  mutating func moveElement(_ id: String, by step: Int) {
    guard let index = elements.firstIndex(where: { $0.id == id }), elements.indices.contains(index + step) else { return }
    elements.swapAt(index, index + step)
  }

  func element(_ id: String) -> EditElement? { elements.first { $0.id == id } }

  /// Gli id che compaiono più di una volta.
  var repeatedIDs: Set<String> {
    var seen = Set<String>(), repeated = Set<String>()
    for element in elements where !seen.insert(element.id).inserted { repeated.insert(element.id) }
    return repeated
  }
}
