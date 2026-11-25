import CoreGraphics
import Foundation

@testable import SeamlessPattern

/// Test pictures built from a formula on 8-bit values (the same formulas are in the Python reference script).
enum TestImages {
  static func make(_ width: Int, _ height: Int, _ f: (Int, Int, Int) -> Int) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        for c in 0..<3 { bytes[(y * width + x) * 4 + c] = UInt8(truncatingIfNeeded: f(x, y, c)) }
      }
    }
    return SPPixels(width: width, height: height, rgba: bytes).cgImage()!
  }

  /// Pixel (x, y) as (r, g, b).
  static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    let p = SPPixels(image)!
    let i = (y * p.width + x) * 4
    return Array(p.rgba[i..<i + 3])
  }
}
