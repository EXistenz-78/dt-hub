import CoreGraphics
import Foundation

/// Why the seam cannot be corrected on a picture (or at all).
enum PFSeamReason: Error, Equatable {
  case noResult
  case unreadable
  case notTwoToOne
  /// The square is as tall as the panorama, so its height must be a multiple of 64.
  case sizeNotMultipleOf64
  case tooBig
}

/// Where everything goes for a panorama `width × height` with `width == 2·height`: the Seamfix square (`side × side`) holds the right end and then the left
/// end of the panorama (a quarter of the width each), so the seam is in the middle, covered by a white bar an eighth of the width wide.
struct PFSeamPlan: Equatable {
  let width: Int
  let height: Int

  var side: Int { height }
  /// The width of each end of the panorama that goes into the square.
  var quarter: Int { width / 4 }
  var barWidth: Int { width / 8 }
  var barX: Int { quarter - barWidth / 2 }
  /// The width of the soft edge on the inner side of each end when it is put back.
  var feather: Int { max(1, quarter / 16) }
}

/// The correction of the seam: the plan for a size and the picture work (all whole pixels except the soft edge and the colour).
enum PFSeam {
  /// The tallest panorama it works on (the square is as tall).
  static let maxHeight = 4096

  /// The plan for a panorama of this size, or why there is none. It must be 2:1 (4 % either way to tell «not 2:1» from «not a multiple of 64», then
  /// exactly 2:1 for the geometry), both sides multiples of 64, and not taller than `maxHeight`.
  static func plan(width: Int, height: Int) -> Result<PFSeamPlan, PFSeamReason> {
    guard width > 0, height > 0, abs(Double(width) / Double(height) / 2 - 1) <= 0.04 else { return .failure(.notTwoToOne) }
    guard width % 64 == 0, height % 64 == 0 else { return .failure(.sizeNotMultipleOf64) }
    guard width == 2 * height else { return .failure(.notTwoToOne) }
    guard height <= maxHeight else { return .failure(.tooBig) }
    return .success(PFSeamPlan(width: width, height: height))
  }

  /// The square: the right end of the panorama, then its left end; with `withBar` the white bar over the seam. nil when the picture is not the plan's size.
  static func square(from panorama: CGImage, plan: PFSeamPlan, withBar: Bool) -> CGImage? {
    guard panorama.width == plan.width, panorama.height == plan.height else { return nil }
    let (bytes, width, height) = PFPixels.rgba(of: panorama)
    let q = plan.quarter, side = plan.side
    var out = [UInt8](repeating: 255, count: side * side * 4)
    for y in 0..<height {
      let src = y * width * 4, dst = y * side * 4
      out.replaceSubrange(dst..<(dst + q * 4), with: bytes[(src + (width - q) * 4)..<(src + width * 4)])
      out.replaceSubrange((dst + q * 4)..<(dst + 2 * q * 4), with: bytes[src..<(src + q * 4)])
      if withBar {
        for x in plan.barX..<(plan.barX + plan.barWidth) {
          let i = dst + x * 4
          out[i] = 255
          out[i + 1] = 255
          out[i + 2] = 255
        }
      }
    }
    return PFPixels.image(bytes: out, width: side, height: side)
  }

  /// The generated square put back into the panorama: its colour brought towards the square's own (without the bar), then each half back at its end of the
  /// panorama with a soft edge (`plan.feather` pixels) on the inner side; the rest of the panorama stays pixel for pixel as it was. nil when a picture is not the
  /// size the plan says.
  static func merge(result: CGImage, into panorama: CGImage, plan: PFSeamPlan, matchingColour: Bool = true) -> CGImage? {
    guard result.width == plan.side, result.height == plan.side, panorama.width == plan.width, panorama.height == plan.height else { return nil }
    var made = result
    if matchingColour {
      guard let reference = square(from: panorama, plan: plan, withBar: false), let matched = matchColour(result, to: reference) else { return nil }
      made = matched
    }
    let (original, width, height) = PFPixels.rgba(of: panorama)
    let (generated, side, _) = PFPixels.rgba(of: made)
    let q = plan.quarter, feather = Float(plan.feather)
    var out = original
    for y in 0..<height {
      for i in 0..<q {
        let weight = min(1, Float(i) / feather)
        // The right end of the panorama is the left half of the square; i counts from the inner edge (column width − q).
        blend(&out, original, generated, at: (y * width + (width - q + i)) * 4, from: (y * side + i) * 4, weight: weight)
        // The left end is the right half; j counts from the inner edge (column q − 1) outwards.
        let x = q - 1 - i
        blend(&out, original, generated, at: (y * width + x) * 4, from: (y * side + q + x) * 4, weight: weight)
      }
    }
    return PFPixels.image(bytes: out, width: width, height: height)
  }

  private static func blend(_ out: inout [UInt8], _ original: [UInt8], _ generated: [UInt8], at o: Int, from g: Int, weight: Float) {
    for c in 0..<3 {
      let value = Float(original[o + c]) * (1 - weight) + Float(generated[g + c]) * weight
      out[o + c] = UInt8(min(255, max(0, value + 0.5)))
    }
    out[o + 3] = 255
  }

  // MARK: colour (Reinhard, in the lαβ space)

  /// The picture with its colour brought towards the reference's: mean and standard deviation matched channel by channel in the lαβ space (Reinhard's colour
  /// transfer). A flat channel only has its mean moved.
  static func matchColour(_ image: CGImage, to reference: CGImage) -> CGImage? {
    let (bytes, width, height) = PFPixels.rgba(of: image)
    let (refBytes, refWidth, refHeight) = PFPixels.rgba(of: reference)
    guard width > 0, height > 0, refWidth > 0, refHeight > 0 else { return nil }
    var source = lab(bytes), target = lab(refBytes)
    let from = statistics(source), to = statistics(target)
    for p in 0..<(source.count / 3) {
      for c in 0..<3 {
        let centred = source[p * 3 + c] - from.mean[c]
        source[p * 3 + c] = (from.spread[c] > 1e-6 ? centred / from.spread[c] * to.spread[c] : centred) + to.mean[c]
      }
    }
    target = []
    var out = bytes
    for p in 0..<(width * height) {
      let l = source[p * 3], a = source[p * 3 + 1], b = source[p * 3 + 2]
      let base: Float = l / root3
      let wide: Float = a / root6
      let logL: Float = base + wide + b / root2
      let logM: Float = base + wide - b / root2
      let logS: Float = base - 2 * wide
      let cone: (Float, Float, Float) = (power10(logL), power10(logM), power10(logS))
      let r: Float = 4.4679 * cone.0 - 3.5873 * cone.1 + 0.1193 * cone.2
      let g: Float = -1.2186 * cone.0 + 2.3809 * cone.1 - 0.1624 * cone.2
      let bl: Float = 0.0497 * cone.0 - 0.2439 * cone.1 + 1.2045 * cone.2
      out[p * 4] = byte(r)
      out[p * 4 + 1] = byte(g)
      out[p * 4 + 2] = byte(bl)
      out[p * 4 + 3] = 255
    }
    return PFPixels.image(bytes: out, width: width, height: height)
  }

  /// Every pixel as (l, α, β): the logarithm of the LMS cone responses, decorrelated.
  private static func lab(_ bytes: [UInt8]) -> [Float] {
    var out = [Float](repeating: 0, count: bytes.count / 4 * 3)
    for p in 0..<(bytes.count / 4) {
      let r: Float = Float(bytes[p * 4]) / 255
      let g: Float = Float(bytes[p * 4 + 1]) / 255
      let b: Float = Float(bytes[p * 4 + 2]) / 255
      let cl: Float = 0.3811 * r + 0.5783 * g + 0.0402 * b
      let cm: Float = 0.1967 * r + 0.7244 * g + 0.0782 * b
      let cs: Float = 0.0241 * r + 0.1288 * g + 0.8444 * b
      let l = log10Clamped(cl), m = log10Clamped(cm), s = log10Clamped(cs)
      out[p * 3] = (l + m + s) / root3
      out[p * 3 + 1] = (l + m - 2 * s) / root6
      out[p * 3 + 2] = (l - m) / root2
    }
    return out
  }

  private static let root2 = Float(2).squareRoot()
  private static let root3 = Float(3).squareRoot()
  private static let root6 = Float(6).squareRoot()

  private static func log10Clamped(_ value: Float) -> Float { Float(log10(Double(max(value, 1e-6)))) }
  private static func power10(_ value: Float) -> Float { Float(pow(10.0, Double(value))) }
  private static func byte(_ value: Float) -> UInt8 { UInt8(min(255, max(0, value * 255 + 0.5))) }

  private static func statistics(_ values: [Float]) -> (mean: [Float], spread: [Float]) {
    let count = Float(max(1, values.count / 3))
    var mean = [Float](repeating: 0, count: 3), spread = [Float](repeating: 0, count: 3)
    for p in 0..<(values.count / 3) { for c in 0..<3 { mean[c] += values[p * 3 + c] } }
    mean = mean.map { $0 / count }
    for p in 0..<(values.count / 3) { for c in 0..<3 { spread[c] += (values[p * 3 + c] - mean[c]) * (values[p * 3 + c] - mean[c]) } }
    return (mean, spread.map { ($0 / count).squareRoot() })
  }
}
