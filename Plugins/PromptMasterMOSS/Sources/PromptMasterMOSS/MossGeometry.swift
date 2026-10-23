import Foundation

/// Larghezza e altezza della Generazione, in pixel. MOSS legge i box in pixel assoluti dal centro: tutto il calcolo
/// parte da qui (spec §5).
struct PixelSize: Equatable, Sendable {
  var width: Int
  var height: Int

  /// Multipli di 16 e positivi: le dimensioni che MOSS accetta.
  var isUsable: Bool { width > 0 && height > 0 && width % 16 == 0 && height % 16 == 0 }
}

/// Un riquadro in frazioni della tela (0–1, origine in alto a sinistra): non dipende dalla risoluzione.
struct FracBox: Codable, Equatable, Sendable {
  var x0: Double
  var y0: Double
  var x1: Double
  var y1: Double

  /// Il lato minimo di un box: il 2 % del lato corto della tela, espresso in frazioni per ciascun asse.
  static let minSide = 0.02

  static func minimum(for size: PixelSize) -> (x: Double, y: Double) {
    let short = Double(min(size.width, size.height))
    return (minSide * short / Double(max(size.width, 1)), minSide * short / Double(max(size.height, 1)))
  }

  /// Estremi in ordine, dentro 0–1; nil se un lato è più corto del minimo.
  static func normalized(x0: Double, y0: Double, x1: Double, y1: Double, size: PixelSize) -> FracBox? {
    func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
    let box = FracBox(x0: clamp(min(x0, x1)), y0: clamp(min(y0, y1)), x1: clamp(max(x0, x1)), y1: clamp(max(y0, y1)))
    let least = minimum(for: size)
    guard box.x1 - box.x0 >= least.x - 1e-9, box.y1 - box.y0 >= least.y - 1e-9 else { return nil }
    return box
  }
}

enum MossGeometry {
  /// Tolleranza dei floor/ceil: `150/1024·1024` in virgola mobile sta appena sotto 150 e non deve dare 149.
  static let epsilon = 1e-6

  /// Gli estremi in pixel dall'angolo, `[left, top, right, bottom]`: sinistra e alto per difetto, destra e basso per eccesso,
  /// dentro la tela.
  private static func edges(_ box: FracBox, in size: PixelSize) -> (l: Int, t: Int, r: Int, b: Int) {
    let w = Double(size.width), h = Double(size.height)
    func low(_ v: Double, _ limit: Double) -> Int { Int(min(limit, max(0, (v + epsilon).rounded(.down)))) }
    func high(_ v: Double, _ limit: Double) -> Int { Int(min(limit, max(0, (v - epsilon).rounded(.up)))) }
    return (low(box.x0 * w, w), low(box.y0 * h, h), high(box.x1 * w, w), high(box.y1 * h, h))
  }

  /// `[y0, x0, y1, x1]` in pixel dal centro (x a destra, y in basso): la forma `abs_centralized` / `yxyx` di MOSS.
  static func centered(_ box: FracBox, in size: PixelSize) -> [Int] {
    let e = edges(box, in: size), halfW = Double(size.width) / 2, halfH = Double(size.height) / 2
    return [
      Int((Double(e.t) - halfH).rounded()), Int((Double(e.l) - halfW).rounded()),
      Int((Double(e.b) - halfH).rounded()), Int((Double(e.r) - halfW).rounded()),
    ]
  }

  /// `[x0, y0, x1, y1]` in pixel dall'angolo in alto a sinistra (come si disegna).
  static func topLeftPixels(_ box: FracBox, in size: PixelSize) -> [Int] {
    let e = edges(box, in: size)
    return [e.l, e.t, e.r, e.b]
  }

  /// Legge `[y0, x0, y1, x1]` dal centro (anche senza parentesi) e lo riporta in frazioni; nil se non sono quattro numeri
  /// o se il lato è sotto il minimo. Gli estremi invertiti si rimettono in ordine; `current` non serve al calcolo ma tiene
  /// la firma allineata a `BBox.resolve` di I4.
  static func parseCentered(_ text: String, current: FracBox, size: PixelSize) -> FracBox? {
    let separators = CharacterSet(charactersIn: "[](), \t\n")
    let tokens = text.components(separatedBy: separators).filter { !$0.isEmpty }
    let numbers = tokens.compactMap(Double.init)
    guard tokens.count == 4, numbers.count == 4 else { return nil }
    let w = Double(size.width), h = Double(size.height)
    return FracBox.normalized(
      x0: (numbers[1] + w / 2) / w, y0: (numbers[0] + h / 2) / h, x1: (numbers[3] + w / 2) / w, y1: (numbers[2] + h / 2) / h,
      size: size)
  }
}
