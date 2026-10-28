import CoreGraphics
import Foundation
import ImageIO

/// Pictures for the tests: made from a function of the pixel, written as PNG, read back pixel by pixel.
enum TestImages {
  static func tempFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Panorama360F3-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  typealias RGB = (UInt8, UInt8, UInt8)

  static func image(width: Int, height: Int, pixel: (Int, Int) -> RGB) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let (r, g, b) = pixel(x, y)
        let i = (y * width + x) * 4
        bytes[i] = r
        bytes[i + 1] = g
        bytes[i + 2] = b
      }
    }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  }

  /// A picture whose red channel is the column and whose green channel is the row (modulo 256), so a test can tell where a pixel came from.
  static func coordinates(width: Int, height: Int) -> CGImage {
    image(width: width, height: height) { x, y in (UInt8(x % 256), UInt8(y % 256), UInt8((x / 256) % 256)) }
  }

  @discardableResult
  static func writePNG(_ image: CGImage, to url: URL) -> URL {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return url
  }

  static func png(width: Int, height: Int, in folder: URL, name: String = "\(UUID().uuidString).png", pixel: (Int, Int) -> RGB = { _, _ in (120, 80, 40) }) -> URL {
    writePNG(image(width: width, height: height, pixel: pixel), to: folder.appendingPathComponent(name))
  }

  static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> RGB {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (bytes[0], bytes[1], bytes[2])
  }

  static func size(of url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (width, height)
  }
}
