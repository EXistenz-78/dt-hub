import CoreGraphics
import Foundation
import ImageIO

@testable import Panorama360

/// Small pictures made in memory for the tests.
enum TestImages {
  static func make(_ width: Int, _ height: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let (r, g, b, a) = pixel(x, y)
        // Premultiplied, like the renderers read them.
        let k = Double(a) / 255
        let i = (y * width + x) * 4
        bytes[i] = UInt8((Double(r) * k).rounded())
        bytes[i + 1] = UInt8((Double(g) * k).rounded())
        bytes[i + 2] = UInt8((Double(b) * k).rounded())
        bytes[i + 3] = a
      }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
      shouldInterpolate: true, intent: .defaultIntent)!
  }

  static func solid(_ w: Int, _ h: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) -> CGImage {
    make(w, h) { _, _ in (r, g, b, a) }
  }

  /// A smooth picture that differs from one seed to the next.
  static func gradient(_ w: Int, _ h: Int, seed: Int) -> CGImage {
    make(w, h) { x, y in
      (UInt8((x * 255 / max(1, w - 1) + seed * 40) % 256), UInt8((y * 255 / max(1, h - 1) + seed * 70) % 256), UInt8(60 + seed * 50), 255)
    }
  }

  /// The pixel (r, g, b, a) of a picture, as 8-bit values.
  static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let pixels = PSPixels.rgba(of: image)
    let i = (y * image.width + x) * 4
    return (Int(pixels.bytes[i]), Int(pixels.bytes[i + 1]), Int(pixels.bytes[i + 2]), Int(pixels.bytes[i + 3]))
  }

  static func layer(_ image: CGImage, yaw: Double = 0, pitch: Double = 0, rot: Double = 0, hfov: Double = 90, opacity: Double = 1) -> PSLayer {
    let sticker = Sticker(name: "t", file: "t", yaw: yaw, pitch: pitch, rot: rot, hfov: hfov)
    return PSLayer(
      image: image, basis: PSProjection.basis(for: sticker, aspect: Double(image.width) / Double(image.height)), opacity: opacity)
  }
}

extension TestImages {
  /// Writes a picture as a file (JPEG or PNG) with the properties given (EXIF and so on); returns its URL.
  static func file(
    _ image: CGImage, in folder: URL, name: String, type: String = "public.jpeg", properties: [CFString: Any] = [:]
  ) -> URL {
    let url = folder.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
    return url
  }

  static func tempFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("p360-img-\(UUID())", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
