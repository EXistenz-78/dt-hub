import Foundation

/// Quale dei due riquadri di un elemento: l'origine (`src`) o la destinazione (`tgt`).
enum BoxRole: String, Sendable { case src, tgt }

/// Un riquadro come lo mostra una tela: di che elemento è, il colore, dove sta, e come si disegna (spec §5): l'origine
/// tratteggiata, la destinazione piena, «Togli» con una X.
struct StageItem: Equatable, Identifiable, Sendable {
  var elementID: String
  var role: BoxRole
  var colorIndex: Int
  var box: BBox
  var dashed: Bool
  var crossed = false
  var caption: String

  /// Unico per riquadro: `<id elemento>|<src|tgt>`.
  var id: String { elementID + "|" + role.rawValue }

  static func parse(_ itemID: String) -> (elementID: String, role: BoxRole)? {
    guard let bar = itemID.lastIndex(of: "|"), let role = BoxRole(rawValue: String(itemID[itemID.index(after: bar)...])) else {
      return nil
    }
    return (String(itemID[..<bar]), role)
  }
}

/// Una freccia dal riquadro «da» a quello «a» di uno spostamento.
struct StageArrow: Equatable, Sendable {
  var from: BBox
  var to: BBox
  var colorIndex: Int
}

extension EditState {
  /// I riquadri della tela dell'immagine del Moodboard mostrata: le origini delle sue coppie.
  var referenceItems: [StageItem] {
    elementsOnShownReference.compactMap { element in
      element.src.map { StageItem(elementID: element.id, role: .src, colorIndex: element.colorIndex, box: $0, dashed: true, caption: element.id) }
    }
  }

  /// I riquadri della tela dell'immagine di partenza. Una coppia la cui immagine non è più nel Moodboard non si disegna.
  var canvasItems: [StageItem] {
    var items: [StageItem] = []
    for element in document.elements where !EditComposer.isMissing(element, refs: refs) {
      func item(_ role: BoxRole, _ box: BBox?, dashed: Bool, crossed: Bool = false, caption: String) {
        guard let box else { return }
        items.append(StageItem(elementID: element.id, role: role, colorIndex: element.colorIndex, box: box, dashed: dashed, crossed: crossed, caption: caption))
      }
      switch element.kind {
      case .fromReference, .new:
        item(.tgt, element.tgt, dashed: false, caption: element.id)
      case .existing:
        item(.src, element.src, dashed: false, caption: L.format(.existingTag, element.id, italian: italian))
      case .move:
        item(.src, element.src, dashed: true, caption: L.format(.moveFrom, element.id, italian: italian))
        item(.tgt, element.tgt, dashed: false, caption: L.format(.moveTo, element.id, italian: italian))
      case .remove:
        item(.src, element.src, dashed: true, crossed: true, caption: L.format(.removeTag, element.id, italian: italian))
      }
    }
    return items
  }

  var arrows: [StageArrow] {
    document.elements.compactMap { element in
      guard element.kind == .move, let from = element.src, let to = element.tgt else { return nil }
      return StageArrow(from: from, to: to, colorIndex: element.colorIndex)
    }
  }

  /// Un gesto finito su una tela: il riquadro `itemID` ha una nuova posizione.
  func setBox(_ box: BBox, itemID: String) {
    guard let (id, role) = StageItem.parse(itemID) else { return }
    update(element: id) { role == .src ? ($0.src = box) : ($0.tgt = box) }
  }

  /// Un clic su un riquadro seleziona il suo elemento (e quindi anche l'altra metà della coppia e la mini-card).
  func selectItem(_ itemID: String?) { selected = itemID.flatMap { StageItem.parse($0)?.elementID } }
}
