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

  /// Draws `image` stretched into `rect` (top left origin, in pixels of this canvas), replacing what was there.
  func draw(_ image: CGImage, in rect: CGRect) {
    context.interpolationQuality = .high
    context.setBlendMode(.copy)
    context.draw(
      image, in: CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
    context.setBlendMode(.normal)
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

/// The small picture the tab shows while a job runs: the enlarged picture and the tiles that are back, at most `maxSide`
/// pixels on the long side (the real picture can be 8192 px: it is never copied for the screen).
enum TUPreview {
  static let maxSide = 1200

  /// How much a picture is reduced to fit `maxSide`; 1 when it already fits (it is never enlarged).
  static func scale(width: Int, height: Int, maxSide: Int = maxSide) -> Double {
    min(1, Double(maxSide) / Double(max(width, height, 1)))
  }

  static func size(width: Int, height: Int, maxSide: Int = maxSide) -> (width: Int, height: Int) {
    let factor = scale(width: width, height: height, maxSide: maxSide)
    return (max(1, Int((Double(width) * factor).rounded())), max(1, Int((Double(height) * factor).rounded())))
  }

  /// A tile's place in the small picture. The edges are rounded, not the sizes, so two tiles that touch in the real
  /// picture touch in the small one, with no gap and no overlap of their own.
  static func rect(of tile: TileRect, scale: Double) -> CGRect {
    let x0 = (Double(tile.x) * scale).rounded()
    let y0 = (Double(tile.y) * scale).rounded()
    let x1 = (Double(tile.x + tile.width) * scale).rounded()
    let y1 = (Double(tile.y + tile.height) * scale).rounded()
    return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  /// The enlarged picture as it will be (enlarged, then cut as `size` says), reduced for the screen.
  static func base(of source: CGImage, factor: Int, size: ScaledSize, maxSide: Int = maxSide) -> CGImage? {
    let shown = Self.size(width: size.width, height: size.height, maxSide: maxSide)
    guard let canvas = TUCanvas(width: shown.width, height: shown.height) else { return nil }
    let s = Double(shown.width) / Double(size.width)
    canvas.draw(
      source,
      in: CGRect(
        x: -Double(size.cropLeft) * s, y: -Double(size.cropTop) * s, width: Double(source.width * factor) * s,
        height: Double(source.height * factor) * s))
    return canvas.image()
  }
}
