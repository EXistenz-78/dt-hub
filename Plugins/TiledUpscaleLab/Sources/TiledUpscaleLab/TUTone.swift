import CoreGraphics
import Foundation

/// The model tends to make a tile lighter or darker than the source, by an amount that depends on what the tile shows, so
/// two neighbours come out at different levels and no fade can hide the step. Here a result is brought back to the source's
/// brightness before it is composed: where the source (enlarged) is brighter or darker than the result over a wide area, the
/// colours of the result are scaled by the ratio of the two. The hue stays, the fine detail stays (the ratio is smooth), only
/// the slow drift of the level is taken out.
enum TUTone {
  /// The most the correction can scale a colour, up or down.
  static let gainRange: ClosedRange<Float> = 0.5...2.0
  /// Over how many pixels, from the edge of the mask, the correction grows from nothing to all.
  static let ramp = 48

  /// `result` is the tile the model made, `base` the enlarged source cut in the same place. `maskRect` is the part the model
  /// regenerated (in the tile): outside it nothing changes, and inside it the correction grows from its edges that touch the
  /// neighbours (the free part is put back as it was and must not step). `radius` is the size of the blur that tells "slow" from
  /// "fine", `strength` how much of the correction is applied (0…1).
  static func correct(result: CGImage, base: CGImage, maskRect: TileRect?, radius: Int, strength: Double) -> CGImage? {
    guard strength > 0, result.width == base.width, result.height == base.height else { return result }
    let width = result.width
    let height = result.height
    guard var pixels = TUImage.rgba(result), let reference = TUImage.rgba(base) else { return nil }
    var lightResult = [Float](repeating: 0, count: width * height)
    var lightBase = [Float](repeating: 0, count: width * height)
    for i in 0..<(width * height) {
      let p = i * 4
      lightResult[i] = 0.2126 * Float(pixels[p]) + 0.7152 * Float(pixels[p + 1]) + 0.0722 * Float(pixels[p + 2])
      lightBase[i] = 0.2126 * Float(reference[p]) + 0.7152 * Float(reference[p + 1]) + 0.0722 * Float(reference[p + 2])
    }
    let slowResult = blur(lightResult, width: width, height: height, radius: radius)
    let slowBase = blur(lightBase, width: width, height: height, radius: radius)
    let amount = Float(min(max(strength, 0), 1))
    for y in 0..<height {
      let wy = edgeWeight(y, from: maskRect?.y ?? 0)
      if wy == 0 { continue }
      for x in 0..<width {
        let w = edgeWeight(x, from: maskRect?.x ?? 0) * wy
        if w == 0 { continue }
        let i = y * width + x
        let gain = min(max((slowBase[i] + 1) / (slowResult[i] + 1), gainRange.lowerBound), gainRange.upperBound)
        let factor = 1 + amount * w * (gain - 1)
        let p = i * 4
        for c in 0..<3 { pixels[p + c] = UInt8(min(max((Float(pixels[p + c]) * factor).rounded(), 0), 255)) }
      }
    }
    return TUImage.image(rgba: pixels, width: width, height: height)
  }

  /// 0 before `start`; from `start` a smooth rise to 1 over `ramp` pixels; 1 everywhere when there is no neighbour (`start` 0).
  private static func edgeWeight(_ position: Int, from start: Int) -> Float {
    if start <= 0 { return 1 }
    if position < start { return 0 }
    let t = min(1, Float(position - start) / Float(ramp))
    return t * t * (3 - 2 * t)
  }

  /// A blur of a grid of numbers: three passes of a box of `radius` on each axis (close to a Gaussian), the edges repeated.
  static func blur(_ values: [Float], width: Int, height: Int, radius: Int) -> [Float] {
    var a = values
    let r = max(radius, 1)
    for _ in 0..<3 {
      a = box(a, width: width, height: height, radius: r, horizontal: true)
      a = box(a, width: width, height: height, radius: r, horizontal: false)
    }
    return a
  }

  private static func box(_ values: [Float], width: Int, height: Int, radius: Int, horizontal: Bool) -> [Float] {
    var out = [Float](repeating: 0, count: values.count)
    let lines = horizontal ? height : width
    let length = horizontal ? width : height
    let scale = 1 / Float(2 * radius + 1)
    for line in 0..<lines {
      func index(_ k: Int) -> Int { horizontal ? line * width + k : k * width + line }
      func at(_ k: Int) -> Float { values[index(min(max(k, 0), length - 1))] }
      var sum: Float = 0
      for k in -radius...radius { sum += at(k) }
      for k in 0..<length {
        out[index(k)] = sum * scale
        sum += at(k + radius + 1) - at(k - radius)
      }
    }
    return out
  }
}
