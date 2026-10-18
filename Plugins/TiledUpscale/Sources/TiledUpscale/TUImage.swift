import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The picture the plug-in works on: RGBA, 8 bits, sRGB, kept in one buffer so a tile is cut out and put back row by row,
/// to the pixel (no resampling between the tile Draw Things gets and the place it comes back to).
final class TUCanvas {
  let width: Int
  let height: Int
  private let context: CGContext

  private static var colorSpace: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB() }

  /// An empty (transparent) canvas.
  init?(width: Int, height: Int) {
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: Self.colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    self.width = width
    self.height = height
    self.context = context
  }

  /// `image` enlarged `factor` times, bilinear, then cut to `size` (the cut starts at `cropLeft`, `cropTop`).
  convenience init?(scaling image: CGImage, factor: Int, size: ScaledSize) {
    self.init(width: size.width, height: size.height)
    let enlargedWidth = image.width * factor
    let enlargedHeight = image.height * factor
    context.interpolationQuality = .low
    context.setBlendMode(.copy)
    // The enlarged picture's top left falls at (-cropLeft, -cropTop); the context's origin is at the bottom left.
    context.draw(
      image,
      in: CGRect(
        x: -size.cropLeft, y: size.height + size.cropTop - enlargedHeight, width: enlargedWidth, height: enlargedHeight))
    context.setBlendMode(.normal)
  }

  /// Puts `tile` (the size of `rect`) at `rect`, replacing what was there.
  func paste(_ tile: CGImage, at rect: TileRect) {
    guard tile.width == rect.width, tile.height == rect.height, rect.x >= 0, rect.y >= 0,
      rect.x + rect.width <= width, rect.y + rect.height <= height,
      let temporary = CGContext(
        data: nil, width: rect.width, height: rect.height, bitsPerComponent: 8, bytesPerRow: rect.width * 4,
        space: Self.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let source = temporary.data, let target = context.data
    else { return }
    temporary.setBlendMode(.copy)
    temporary.draw(tile, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    let rowBytes = rect.width * 4
    for row in 0..<rect.height {
      memcpy(
        target + (rect.y + row) * width * 4 + rect.x * 4, source + row * rowBytes, rowBytes)
    }
  }

  /// A copy of the part at `rect`.
  func crop(_ rect: TileRect) -> CGImage? {
    guard rect.width > 0, rect.height > 0, rect.x >= 0, rect.y >= 0, rect.x + rect.width <= width,
      rect.y + rect.height <= height,
      let temporary = CGContext(
        data: nil, width: rect.width, height: rect.height, bitsPerComponent: 8, bytesPerRow: rect.width * 4,
        space: Self.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let target = temporary.data, let source = context.data
    else { return nil }
    let rowBytes = rect.width * 4
    for row in 0..<rect.height {
      memcpy(target + row * rowBytes, source + (rect.y + row) * width * 4 + rect.x * 4, rowBytes)
    }
    return temporary.makeImage()
  }

  /// The whole picture.
  func image() -> CGImage? { context.makeImage() }
}

enum TUImage {
  /// A grey PNG, `width` × `height`: 255 inside `masked` (the part the model regenerates), 0 elsewhere (all 0 for nil).
  static func maskPNG(width: Int, height: Int, masked: TileRect?) -> Data? {
    guard width > 0, height > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: width * height)
    if let masked {
      let x0 = max(0, masked.x)
      let x1 = min(width, masked.x + masked.width)
      let y0 = max(0, masked.y)
      let y1 = min(height, masked.y + masked.height)
      if x0 < x1, y0 < y1 {
        for y in y0..<y1 { for x in x0..<x1 { bytes[y * width + x] = 255 } }
      }
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return nil }
    return pngData(image)
  }

  static func pngData(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
      return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }

  /// A picture from data (a drop); nil when it cannot be read.
  static func load(data: Data) -> CGImage? {
    CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
  }

  /// The picture in a file, at its own size; nil when it cannot be read.
  static func load(_ url: URL) -> CGImage? {
    CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
  }
}
