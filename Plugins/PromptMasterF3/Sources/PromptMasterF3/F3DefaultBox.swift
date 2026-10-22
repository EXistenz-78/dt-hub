import Foundation

/// Il box di un id nuovo (spec §8): in fila da in alto a sinistra, senza sovrapporsi, perché l'utente scrive prima tutti gli id e
/// poi li posiziona. Lato 180 su 1000 (quadrato in pixel), passo 200, a capo a destra; con la griglia piena si sfalsa.
enum F3DefaultBox {
  static let side = 180
  static let step = 200

  /// `aspect` = larghezza / altezza della generazione.
  static func box(index: Int, aspect: Double, taken: [BBox]) -> BBox {
    let grid = BBoxScale.grid
    let ratio = aspect.isFinite && aspect > 0 ? aspect : 1
    let width = side
    let height = min(max(Int((Double(side) * ratio).rounded()), BBox.minSide), grid)
    let rowStep = max(step, height + 20)
    let columns = max(1, (grid - width) / step + 1)
    let rows = max(1, (grid - height) / rowStep + 1)
    let capacity = columns * rows
    let slot = max(0, index)
    let lap = slot / capacity
    let place = slot % capacity
    func make(_ extra: Int) -> BBox {
      let y0 = min(max((place / columns) * rowStep + extra, 0), grid - height)
      let x0 = min(max((place % columns) * step + extra, 0), grid - width)
      return BBox(y0: y0, x0: x0, y1: y0 + height, x1: x0 + width)
    }
    // Sfalsa in diagonale, avanti e indietro, finché trova un posto libero (sempre dentro la griglia).
    for k in lap..<(lap + 120) {
      for sign in [1, -1] {
        let candidate = make(sign * k * 20)
        if !taken.contains(candidate) { return candidate }
      }
    }
    return make(0)
  }
}
