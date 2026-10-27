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

  /// The panorama (still rolled) with the band of the generated panorama (the same size) pasted in: its colour brought towards the original's, and its
  /// two edges faded into the original over `plan.fade` pixels. nil when the pictures are not the size the plan says.
  ///
  /// The colour is matched channel by channel (red, green and blue each get their own gain), so a band the model made paler or less saturated than
  /// the sky around it, and not only a darker or lighter one, comes back to the colours of its two sides.
  static func compose(rolled: CGImage, generated: CGImage, plan: PSSeamPlan) -> CGImage? {
    guard rolled.width == plan.width, rolled.height == plan.height, generated.width == plan.width, generated.height == plan.height else {
      return nil
    }
    let (original, width, height) = PSPixels.rgba(of: rolled)
    let (made, _, _) = PSPixels.rgba(of: generated)
    let band = plan.bandWidth
    // The level to match is the one of the panorama OUTSIDE the band, on its two sides (a strip as wide as the fade, beside the band): the gain
    // goes from the left level to the right one, row by row, so a colour or exposure step across the seam is not copied by the new picture.
    let radius = max(1, plan.height / PSSeam.toneRadiusDivisor)
    let strip = max(1, min(plan.fade, plan.bandX))
    let madeLeft = levels(made, width: width, height: height, column: plan.bandX + min(band - 1, strip / 2), radius: radius)
    let madeRight = levels(made, width: width, height: height, column: plan.bandX + max(0, band - 1 - strip / 2), radius: radius)
    let sideLeft = levels(original, width: width, height: height, column: max(0, plan.bandX - 1 - strip / 2), radius: radius)
    let sideRight = levels(original, width: width, height: height, column: min(width - 1, plan.bandX + band + strip / 2), radius: radius)
    var out = original
    for y in 0..<height {
      var gainLeft = [Float](repeating: 1, count: 3), gainRight = [Float](repeating: 1, count: 3)
      for c in 0..<3 {
        gainLeft[c] = min(5, max(0.2, (sideLeft[c][y] + 1) / (madeLeft[c][y] + 1)))
        gainRight[c] = min(5, max(0.2, (sideRight[c][y] + 1) / (madeRight[c][y] + 1)))
      }
      for i in 0..<band {
        let along = Float(i) / Float(max(1, band - 1))
        let weight = fadeWeight(distanceToEdge: Double(min(i, band - 1 - i)) + 0.5, fade: plan.fade)
        let o = (y * width + plan.bandX + i) * 4
        for c in 0..<3 {
          let gain = gainLeft[c] + (gainRight[c] - gainLeft[c]) * along
          let corrected = min(255, Float(made[o + c]) * gain)
          out[o + c] = UInt8(min(255, max(0, Float(original[o + c]) * (1 - weight) + corrected * weight + 0.5)))
        }
      }
    }
    return PSPixels.image(bytes: out, width: width, height: height)
  }

  /// How much of the generated picture there is at `distanceToEdge` pixels from the nearest edge of the band: 0 at the edge, 1 from `fade` pixels in
  /// (a smoothstep, so the join has no corner).
  static func fadeWeight(distanceToEdge: Double, fade: Int) -> Float {
    let t = min(1, max(0, distanceToEdge / Double(max(1, fade))))
    return Float(t * t * (3 - 2 * t))
  }

  /// The level of each channel around one column, row by row: the mean of the pixels within `radius` of `column` across and down (edges clamped).
  private static func levels(_ bytes: [UInt8], width: Int, height: Int, column: Int, radius: Int) -> [[Float]] {
    let from = max(0, column - radius), to = min(width - 1, column + radius)
    return (0..<3).map { c in
      var across = [Float](repeating: 0, count: height)
      for y in 0..<height {
        var sum = 0
        for x in from...to { sum += Int(bytes[(y * width + x) * 4 + c]) }
        across[y] = Float(sum) / Float(to - from + 1)
      }
      var down = across
      for y in 0..<height {
        var sum: Float = 0
        for k in -radius...radius { sum += across[min(height - 1, max(0, y + k))] }
        down[y] = sum / Float(2 * radius + 1)
      }
      return down
    }
  }
}
