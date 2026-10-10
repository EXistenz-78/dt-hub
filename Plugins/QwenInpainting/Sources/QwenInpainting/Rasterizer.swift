import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The marks as a PNG, and the start image with the marks on it.
enum Rasterizer {
  /// The longest side of the PNG of the drawing: the app keeps the layer small anyway.
  static let paintMaxSide = 2048

  /// The size of the picture as it is shown (the EXIF orientation applied).
  static func imageSize(at path: String) -> CGSize? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
  }

  /// The picture upright, its longest side at most `maxSide` (the whole picture when nil).
  static func orientedImage(at path: String, maxSide: Int?) -> CGImage? {
    guard let size = imageSize(at: path), let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { return nil }
    let longest = Int(max(size.width, size.height))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: min(maxSide ?? longest, longest),
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  private static func context(width: Int, height: Int) -> CGContext? {
    CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  }

  /// The marks on a transparent RGBA picture of `size`; the colours are the pure colours, antialiased. `imageWidth` is the width
  /// of the start image the widths of the marks refer to (`size` when nil).
  static func paint(_ marks: [Mark], size: CGSize, imageWidth: Double? = nil) -> CGImage? {
    let width = Int(size.width.rounded())
    let height = Int(size.height.rounded())
    guard width > 0, height > 0, let context = context(width: width, height: height) else { return nil }
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    // The marks are in coordinates from the top: turn the context over.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    for mark in marks {
      let (red, green, blue) = mark.color.rgb
      let color = (CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255)
      let geometry = MarkGeometry.paths(for: mark, in: CGSize(width: width, height: height), imageWidth: imageWidth ?? Double(width))
      context.setStrokeColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
      context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
      context.setLineWidth(geometry.lineWidth)
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.addPath(geometry.stroke)
      context.strokePath()
      if let fill = geometry.fill {
        context.addPath(fill)
        context.fillPath()
      }
    }
    return context.makeImage()
  }

  /// The start image with the drawing over it, the longest side at most `maxSide`.
  static func fused(start: CGImage, paint: CGImage, maxSide: Int) -> CGImage? {
    let scale = min(1, Double(maxSide) / Double(max(start.width, start.height)))
    let width = max(1, Int((Double(start.width) * scale).rounded()))
    let height = max(1, Int((Double(start.height) * scale).rounded()))
    guard let context = context(width: width, height: height) else { return nil }
    context.interpolationQuality = .high
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    context.draw(start, in: rect)
    context.draw(paint, in: rect)
    return context.makeImage()
  }

  static func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
  }

  /// One pixel, read back (row 0 at the top); for tests and checks.
  static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
    guard let context = context(width: image.width, height: image.height), let data = context.data else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pointer = data.assumingMemoryBound(to: UInt8.self)
    // The first row in memory is the top of the picture.
    let base = y * context.bytesPerRow + x * 4
    return (pointer[base], pointer[base + 1], pointer[base + 2], pointer[base + 3])
  }
}
