import CoreGraphics
import Foundation
import ImageIO

@testable import TiledUpscale

/// Small helpers for the tests that need pictures.
enum TestImages {
  static let space = CGColorSpace(name: CGColorSpace.sRGB)!

  /// A picture of one colour, or one colour left of `splitX` and another right of it.
  static func solid(_ width: Int, _ height: Int, _ rgb: (UInt8, UInt8, UInt8), right: (UInt8, UInt8, UInt8)? = nil, splitX: Int = 0) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let (r, g, b) = (right != nil && x >= splitX) ? right! : rgb
        let base = (y * width + x) * 4
        bytes[base] = r
        bytes[base + 1] = g
        bytes[base + 2] = b
      }
    }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  }

  /// Writes the picture as a PNG and returns its URL.
  static func write(_ image: CGImage, in folder: URL, name: String) -> URL {
    let url = folder.appendingPathComponent(name)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? TUImage.pngData(image)?.write(to: url)
    return url
  }

  /// The RGBA of a pixel of a picture.
  static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setBlendMode(.copy)
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return data
  }

  static func temporaryFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("TiledUpscaleTests-\(UUID())")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
