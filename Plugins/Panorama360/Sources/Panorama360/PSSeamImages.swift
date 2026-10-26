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

  /// `width` columns from column `x`, at the full height; nil when they are not all inside the picture.
  static func crop(_ image: CGImage, x: Int, width: Int) -> CGImage? {
    let (bytes, fullWidth, height) = PSPixels.rgba(of: image)
    guard x >= 0, width > 0, x + width <= fullWidth else { return nil }
    var out = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      out.replaceSubrange(
        (y * width * 4)..<((y + 1) * width * 4), with: bytes[((y * fullWidth + x) * 4)..<((y * fullWidth + x + width) * 4)])
    }
    return PSPixels.image(bytes: out, width: width, height: height)
  }

  /// The mask of the pass: a grey PNG `square × square`, 255 in the central `bandWidth` columns, 0 elsewhere.
  static func maskPNG(square: Int, bandWidth: Int) -> Data? {
    guard square > 0, bandWidth > 0, bandWidth <= square else { return nil }
    let start = (square - bandWidth) / 2
    var bytes = [UInt8](repeating: 0, count: square * square)
    for y in 0..<square { for x in start..<(start + bandWidth) { bytes[y * square + x] = 255 } }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
      let image = CGImage(
        width: square, height: square, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: square,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return nil }
    return pngData(image)
  }

  static func pngData(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }

  /// The panorama (still rolled) with the band of the generated square pasted in: its brightness brought towards the original's, and its two edges
  /// faded into the original over `plan.fade` pixels. nil when the pictures are not the size the plan says.
  static func compose(rolled: CGImage, generated: CGImage, plan: PSSeamPlan) -> CGImage? {
    guard rolled.width == plan.width, rolled.height == plan.height, generated.width == plan.square, generated.height == plan.square else {
      return nil
    }
    let (original, width, height) = PSPixels.rgba(of: rolled)
    let (made, side, _) = PSPixels.rgba(of: generated)
    let band = plan.bandWidth
    let offset = (side - band) / 2
    // The brightness of the band in both pictures, over a wide window: the generated one is scaled by the ratio, so the slow drift of the level goes
    // and the detail stays.
    var lightOriginal = [Float](repeating: 0, count: band * height)
    var lightMade = [Float](repeating: 0, count: band * height)
    for y in 0..<height {
      for i in 0..<band {
        let o = (y * width + plan.bandX + i) * 4
        let g = (y * side + offset + i) * 4
        lightOriginal[y * band + i] = luminance(original, o)
        lightMade[y * band + i] = luminance(made, g)
      }
    }
    let radius = max(1, plan.square / PSSeam.toneRadiusDivisor)
    let blurredOriginal = boxBlur(lightOriginal, width: band, height: height, radius: radius)
    let blurredMade = boxBlur(lightMade, width: band, height: height, radius: radius)
    var out = original
    for y in 0..<height {
      for i in 0..<band {
        let gain = min(5, max(0.2, (blurredOriginal[y * band + i] + 1) / (blurredMade[y * band + i] + 1)))
        let edge = Double(min(i, band - 1 - i)) + 0.5
        let t = min(1, max(0, edge / Double(max(1, plan.fade))))
        let weight = Float(t * t * (3 - 2 * t))
        let o = (y * width + plan.bandX + i) * 4
        let g = (y * side + offset + i) * 4
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
