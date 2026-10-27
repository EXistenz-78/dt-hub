import CoreGraphics
import Foundation
import ImageIO

/// The picture work of the seam correction. Everything moves whole pixels (no resampling) except the soft edge and the brightness correction.
enum PSSeamImages {
  /// The picture with its columns moved: column `x` of the result is column `(x + columns) % width` of the original.
  static func rolled(_ image: CGImage, by columns: Int) -> CGImage? {
    let (bytes, width, height) = PSPixels.rgba(of: image)
    guard width > 0, height > 0 else { return nil }
    let k = ((columns % width) + width) % width
    var out = [UInt8](repeating: 255, count: bytes.count)
    for y in 0..<height {
      let row = y * width * 4
      // The first `width − k` columns of the result are the last `width − k` of the original, starting at column `k`.
      out.replaceSubrange(row..<(row + (width - k) * 4), with: bytes[(row + k * 4)..<(row + width * 4)])
      out.replaceSubrange((row + (width - k) * 4)..<(row + width * 4), with: bytes[row..<(row + k * 4)])
    }
    return PSPixels.image(bytes: out, width: width, height: height)
  }

  /// The picture with `width` columns from column `x`, at the full height, painted green (0, 255, 0): the colour the model fills as an outpaint.
  /// nil when they are not all inside the picture.
  static func paintGreen(_ image: CGImage, x: Int, width: Int) -> CGImage? {
    var (bytes, fullWidth, height) = PSPixels.rgba(of: image)
    guard x >= 0, width > 0, x + width <= fullWidth, height > 0 else { return nil }
    for y in 0..<height {
      for column in x..<(x + width) {
        let i = (y * fullWidth + column) * 4
        bytes[i] = 0
        bytes[i + 1] = 255
        bytes[i + 2] = 0
        bytes[i + 3] = 255
      }
    }
    return PSPixels.image(bytes: bytes, width: fullWidth, height: height)
  }

  static func pngData(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }

  /// The panorama (still rolled) with the band of the generated panorama (the same size) pasted in: its brightness brought towards the original's, and its two edges
  /// faded into the original over `plan.fade` pixels. nil when the pictures are not the size the plan says.
  static func compose(rolled: CGImage, generated: CGImage, plan: PSSeamPlan) -> CGImage? {
    guard rolled.width == plan.width, rolled.height == plan.height, generated.width == plan.width, generated.height == plan.height else {
      return nil
    }
    let (original, width, height) = PSPixels.rgba(of: rolled)
    let (made, _, _) = PSPixels.rgba(of: generated)
    let band = plan.bandWidth
    // The level to match is the one of the panorama OUTSIDE the band, on its two sides (a strip as wide as the fade, beside the band): the gain
    // goes from the left level to the right one, row by row, so an exposure step across the seam is not copied by the new picture.
    let radius = max(1, plan.height / PSSeam.toneRadiusDivisor)
    var lightMade = [Float](repeating: 0, count: band * height)
    var lightOriginal = [Float](repeating: 0, count: width * height)
    for y in 0..<height {
      for i in 0..<band { lightMade[y * band + i] = luminance(made, (y * width + plan.bandX + i) * 4) }
      for x in 0..<width { lightOriginal[y * width + x] = luminance(original, (y * width + x) * 4) }
    }
    let blurredMade = boxBlur(lightMade, width: band, height: height, radius: radius)
    let blurredOriginal = boxBlur(lightOriginal, width: width, height: height, radius: radius)
    let strip = max(1, min(plan.fade, plan.bandX))
    var out = original
    for y in 0..<height {
      // The brightness of the generated picture at its two edges (blurred), and of the panorama just outside the band.
      let madeLeft = blurredMade[y * band + min(band - 1, strip / 2)], madeRight = blurredMade[y * band + max(0, band - 1 - strip / 2)]
      let sideLeft = blurredOriginal[y * width + max(0, plan.bandX - 1 - strip / 2)]
      let sideRight = blurredOriginal[y * width + min(width - 1, plan.bandX + band + strip / 2)]
      let gainLeft = min(5, max(0.2, (sideLeft + 1) / (madeLeft + 1)))
      let gainRight = min(5, max(0.2, (sideRight + 1) / (madeRight + 1)))
      for i in 0..<band {
        let along = Float(i) / Float(max(1, band - 1))
        let gain = gainLeft + (gainRight - gainLeft) * along
        let edge = Double(min(i, band - 1 - i)) + 0.5
        let t = min(1, max(0, edge / Double(max(1, plan.fade))))
        let weight = Float(t * t * (3 - 2 * t))
        let o = (y * width + plan.bandX + i) * 4
        let g = o
        for c in 0..<3 {
          let corrected = min(255, Float(made[g + c]) * gain)
          out[o + c] = UInt8(min(255, max(0, Float(original[o + c]) * (1 - weight) + corrected * weight + 0.5)))
        }
      }
    }
    return PSPixels.image(bytes: out, width: width, height: height)
  }

  private static func luminance(_ bytes: [UInt8], _ i: Int) -> Float {
    0.2126 * Float(bytes[i]) + 0.7152 * Float(bytes[i + 1]) + 0.0722 * Float(bytes[i + 2])
  }

  /// A box blur (edges clamped), the horizontal then the vertical pass, with running sums.
  private static func boxBlur(_ values: [Float], width: Int, height: Int, radius: Int) -> [Float] {
    func pass(_ input: [Float], length: Int, lines: Int, stride step: Int, lineStride: Int) -> [Float] {
      var output = input
      let size = Float(2 * radius + 1)
      for line in 0..<lines {
        let base = line * lineStride
        var sum: Float = 0
        for k in -radius...radius { sum += input[base + min(length - 1, max(0, k)) * step] }
        for i in 0..<length {
          output[base + i * step] = sum / size
          sum += input[base + min(length - 1, i + radius + 1) * step] - input[base + min(length - 1, max(0, i - radius)) * step]
        }
      }
      return output
    }
    let horizontal = pass(values, length: width, lines: height, stride: 1, lineStride: width)
    return pass(horizontal, length: height, lines: width, stride: width, lineStride: 1)
  }
}
