import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What the Brush tool draws over the start image (tab Control spec §3): RGBA, 8 bits, straight
/// (not premultiplied) alpha, at the same working size as the mask (the image's ratio, the longest
/// side at most `MaskBitmap.maxSide`). It is a layer of its own: the start image's file is not
/// touched, and a RUN puts the drawing over the image (`InputComposer.frame`).
public struct PaintBitmap: Equatable, Sendable {
  public let width: Int
  public let height: Int
  /// R, G, B, A for each pixel, row by row.
  public private(set) var pixels: [UInt8]

  public init(width: Int, height: Int) {
    self.width = max(width, 1)
    self.height = max(height, 1)
    pixels = [UInt8](repeating: 0, count: self.width * self.height * 4)
  }

  /// True when nothing is drawn.
  public var isEmpty: Bool {
    for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] > 0 { return false }
    return true
  }

  public func alpha(x: Int, y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }

  public func color(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
    let base = (y * width + x) * 4
    return (pixels[base], pixels[base + 1], pixels[base + 2])
  }

  /// Draws a round, hard brush of `radius` pixels along the segment, in layer pixels. The edge has
  /// one pixel of antialiasing; a pixel keeps the strongest cover it got, so going over the same
  /// place again does not thicken the edge. With a `clip` (in layer pixels) only the pixels whose
  /// centre is inside it are touched. Returns the rectangle of pixels that may have changed, or nil
  /// when nothing could (the segment is outside the layer or the clip).
  @discardableResult
  public mutating func stroke(
    from start: CGPoint, to end: CGPoint, radius: Double, red: UInt8, green: UInt8, blue: UInt8,
    clip: CGRect? = nil
  ) -> CGRect? {
    let radius = max(radius, 0.5)
    let length = hypot(end.x - start.x, end.y - start.y)
    let steps = max(1, Int((length / max(radius / 3, 0.5)).rounded(.up)))
    var dirty: CGRect?
    for step in 0...steps {
      let t = Double(step) / Double(steps)
      let area = stamp(
        at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), radius: radius,
        red: red, green: green, blue: blue, clip: clip)
      if let area { dirty = dirty.map { $0.union(area) } ?? area }
    }
    return dirty
  }

  private mutating func stamp(
    at center: CGPoint, radius: Double, red: UInt8, green: UInt8, blue: UInt8, clip: CGRect?
  ) -> CGRect? {
    var minX = max(0, Int((center.x - radius - 1).rounded(.down)))
    var maxX = min(width - 1, Int((center.x + radius + 1).rounded(.up)))
    var minY = max(0, Int((center.y - radius - 1).rounded(.down)))
    var maxY = min(height - 1, Int((center.y + radius + 1).rounded(.up)))
    if let clip {
      minX = max(minX, Int((clip.minX - 0.5).rounded(.up)))
      maxX = min(maxX, Int((clip.maxX - 0.5).rounded(.up)) - 1)
      minY = max(minY, Int((clip.minY - 0.5).rounded(.up)))
      maxY = min(maxY, Int((clip.maxY - 0.5).rounded(.up)) - 1)
    }
    guard minX <= maxX, minY <= maxY else { return nil }
    for y in minY...maxY {
      for x in minX...maxX {
        let distance = hypot(Double(x) + 0.5 - center.x, Double(y) + 0.5 - center.y)
        let cover = min(1, max(0, radius + 0.5 - distance))
        guard cover > 0 else { continue }
        let base = (y * width + x) * 4
        let now = Double(pixels[base + 3]) / 255
        if cover >= now {
          pixels[base] = red
          pixels[base + 1] = green
          pixels[base + 2] = blue
          pixels[base + 3] = UInt8((cover * 255).rounded())
        } else {
          // The edge of a new stroke over an older, stronger one: the colour leans toward the new one.
          pixels[base] = UInt8((Double(pixels[base]) * (1 - cover) + Double(red) * cover).rounded())
          pixels[base + 1] = UInt8((Double(pixels[base + 1]) * (1 - cover) + Double(green) * cover).rounded())
          pixels[base + 2] = UInt8((Double(pixels[base + 2]) * (1 - cover) + Double(blue) * cover).rounded())
        }
      }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
  }

  public mutating func clear() {
    pixels = [UInt8](repeating: 0, count: pixels.count)
  }

  // MARK: Files and images

  /// The drawing as an image with straight alpha: to show, to put over the start image.
  public func cgImage() -> CGImage? {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  public func pngData() -> Data? {
    guard let image = cgImage() else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }

  /// A drawing read back from its PNG, at the PNG's own size.
  public init?(image: CGImage) {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    // Back to straight alpha.
    for base in stride(from: 0, to: bytes.count, by: 4) where bytes[base + 3] > 0 && bytes[base + 3] < 255 {
      let alpha = Double(bytes[base + 3]) / 255
      for channel in 0..<3 { bytes[base + channel] = UInt8(min(255, (Double(bytes[base + channel]) / alpha).rounded())) }
    }
    self.width = width
    self.height = height
    pixels = bytes
  }
}
