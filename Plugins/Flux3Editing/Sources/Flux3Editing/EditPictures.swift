import Foundation

/// Un riquadro da disegnare su un'immagine che va all'LLM: l'id, il colore dell'elemento (lo stesso del tab), il box sulla tela
/// (griglia 0–1000) e come si disegna.
struct OverlayBox: Equatable, Sendable {
  enum Style: Equatable, Sendable {
    /// Dove sta o dove andrà l'oggetto.
    case solid
    /// Dove stava un oggetto spostato.
    case dashedFrom
    /// Dove stava un oggetto tolto.
    case dashedRemoved
  }

  var id: String
  var colorIndex: Int
  var box: BBox
  var style: Style

  /// La scritta sul riquadro: l'id, e per i tratteggiati che cosa significano.
  var caption: String {
    switch style {
    case .solid: return id
    case .dashedFrom: return "\(id) (from)"
    case .dashedRemoved: return "\(id) (removed)"
    }
  }
}

/// Un'immagine che il piano manda all'LLM: `number` è quello di `<ref_image_N>` (0 = l'immagine di partenza, la tela).
struct PlannedPicture: Equatable, Sendable {
  enum Role: Equatable, Sendable { case start, reference }

  var number: Int
  var role: Role
  var boxes: [OverlayBox]
}

/// Un'immagine già disegnata e scritta su disco, pronta per l'LLM, nell'ordine in cui parte (`path` è il PNG con i riquadri).
struct EditPicture: Equatable, Sendable {
  var number: Int
  var role: PlannedPicture.Role
  var path: String
}

struct EditPicturePlan: Equatable, Sendable {
  var pictures: [PlannedPicture]
  /// I numeri delle reference usate che non entrano nel tetto delle immagini.
  var dropped: [Int]
}

/// Quali immagini vanno all'LLM e con quali riquadri (spec «Flux3 Editing: l'LLM vede le immagini»): quella di partenza, con i
/// riquadri di tutti gli elementi sulla tela, e solo le reference che almeno un elemento usa, con il riquadro di origine.
enum EditPictures {
  /// L'immagine di partenza più al più cinque reference: un modello da 8B con più immagini rallenta e risponde peggio.
  static let maxPictures = 6

  static func plan(document: EditDocument, refs: [RefImage], hasStartImage: Bool, maxPictures: Int = EditPictures.maxPictures) -> EditPicturePlan {
    var pictures: [PlannedPicture] = []
    if hasStartImage { pictures.append(PlannedPicture(number: RefNumbering.startImageNumber, role: .start, boxes: startBoxes(document))) }
    var used: [Int: [OverlayBox]] = [:]
    for element in document.elements where element.kind == .fromReference {
      guard let file = element.refFile, let ref = refs.first(where: { $0.fileName == file }), let source = element.src else { continue }
      used[ref.number, default: []].append(OverlayBox(id: element.id, colorIndex: element.colorIndex, box: source, style: .solid))
    }
    let numbers = used.keys.sorted()
    let room = max(0, maxPictures - pictures.count)
    for number in numbers.prefix(room) {
      pictures.append(PlannedPicture(number: number, role: .reference, boxes: used[number] ?? []))
    }
    return EditPicturePlan(pictures: pictures, dropped: Array(numbers.dropFirst(room)))
  }

  /// I riquadri sulla tela dell'immagine di partenza, nell'ordine degli elementi.
  private static func startBoxes(_ document: EditDocument) -> [OverlayBox] {
    var boxes: [OverlayBox] = []
    for element in document.elements {
      func add(_ box: BBox?, _ style: OverlayBox.Style) {
        if let box { boxes.append(OverlayBox(id: element.id, colorIndex: element.colorIndex, box: box, style: style)) }
      }
      switch element.kind {
      case .fromReference, .new: add(element.tgt, .solid)
      case .existing: add(element.src, .solid)
      case .move:
        add(element.src, .dashedFrom)
        add(element.tgt, .solid)
      case .remove: add(element.src, .dashedRemoved)
      }
    }
    return boxes
  }
}
