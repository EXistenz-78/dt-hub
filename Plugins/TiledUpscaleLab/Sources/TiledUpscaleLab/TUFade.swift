import CoreGraphics
import Foundation

/// The join between what the neighbours already made and what is still the enlarged source, inside the picture that is sent to
/// the model. Left as it is, the picture has a hard edge there (sharp, tone of the neighbour on one side, soft, tone of the
/// source on the other) that the model takes for a part of the picture and repeats. Here the neighbour's result is faded into
/// the source over `fade` pixels, ending at the end of the overlap.
enum TUFade {
  /// How much of the neighbour's result (against the source) a pixel of the tile has: 1 deep in the part the neighbours made, 0
  /// from the end of the overlap on, a smooth ramp in the `fade` pixels before it, rounded at the inner corner when there are
  /// two neighbours. With no fade the edge is hard (1 in the part the neighbours made, 0 outside).
  static func weight(x: Int, y: Int, column: Int, row: Int, overlap: Int, fade: Int) -> Double {
    let xStart = column > 0 ? overlap : 0
    let yStart = row > 0 ? overlap : 0
    let dx = Double(max(0, xStart - x))
    let dy = Double(max(0, yStart - y))
    let distance = (dx * dx + dy * dy).squareRoot()
    guard distance > 0 else { return 0 }
    guard fade > 0 else { return 1 }
    let t = min(1, distance / Double(fade))
    return t * t * (3 - 2 * t)
  }

  /// The tile as the model gets it: `canvas` (the picture composed so far, which holds the neighbours' results) where the weight
  /// is 1, `base` (the enlarged source) where it is 0, a mix between. Both are the tile's cut, the same size. Only the pixels
  /// in the ramp change.
  static func apply(canvas: CGImage, base: CGImage, column: Int, row: Int, overlap: Int, fade: Int) -> CGImage? {
    guard fade > 0, canvas.width == base.width, canvas.height == base.height else { return canvas }
    let width = canvas.width
    let height = canvas.height
    guard var pixels = TUImage.rgba(canvas), let source = TUImage.rgba(base) else { return nil }
    let xStart = column > 0 ? overlap : 0
    let yStart = row > 0 ? overlap : 0
    for y in 0..<height {
      for x in 0..<width {
        // Only where the distance to the part still to do is under `fade`.
        if x >= xStart + 0 && y >= yStart + 0 { continue }
        let dx = max(0, xStart - x)
        let dy = max(0, yStart - y)
        if dx >= fade || dy >= fade { continue }
        let w = Float(weight(x: x, y: y, column: column, row: row, overlap: overlap, fade: fade))
        if w >= 1 { continue }
        let i = (y * width + x) * 4
        for c in 0..<3 {
          pixels[i + c] = UInt8((Float(pixels[i + c]) * w + Float(source[i + c]) * (1 - w)).rounded())
        }
      }
    }
    return TUImage.image(rgba: pixels, width: width, height: height)
  }
}
