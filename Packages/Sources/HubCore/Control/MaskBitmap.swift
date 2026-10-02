import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The inpaint mask as the tab draws it (tab Control spec §3): one byte per pixel, 255 where the
/// picture is to be regenerated. It lives at a working size (the start image's ratio, its longest
/// side at most 1024 px) so the brush stays fluent on any image; a RUN scales it to the canvas.
/// Draw Things takes a mask with no shades, so the brush has no softness: the edge is softened
/// there (`MaskSettings.blur`).
public struct MaskBitmap: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public private(set) var pixels: [UInt8]

  /// Longest side of the working mask.
  public static let maxSide = 1024

  public init(width: Int, height: Int) {
    self.width = max(width, 1)
    self.height = max(height, 1)
    pixels = [UInt8](repeating: 0, count: self.width * self.height)
  }

  /// The working size for an image: its ratio, the longest side at most `maxSide`.
  public static func workingSize(imageWidth: Int, imageHeight: Int) -> (width: Int, height: Int) {
    let longest = max(imageWidth, imageHeight, 1)
    let scale = min(1, Double(maxSide) / Double(longest))
    return (max(1, Int((Double(imageWidth) * scale).rounded())), max(1, Int((Double(imageHeight) * scale).rounded())))
  }

  /// True when nothing is painted.
  public var isEmpty: Bool { !pixels.contains { $0 >= 128 } }

  /// The share of the whole mask that is painted, 0…1.
  public var coverage: Double {
    Double(pixels.reduce(0) { $0 + ($1 >= 128 ? 1 : 0) }) / Double(pixels.count)
  }

  // MARK: Drawing

  /// Paints (or erases) a round brush of `radius` pixels along the segment from `start` to `end`,
  /// in mask pixels. The edge has one pixel of antialiasing. Returns the rectangle of pixels that
  /// may have changed (empty when the segment is outside the mask), so a view can update only that.
  @discardableResult
  public mutating func stroke(from start: CGPoint, to end: CGPoint, radius: Double, erase: Bool) -> CGRect {
    let radius = max(radius, 0.5)
    let length = hypot(end.x - start.x, end.y - start.y)
    let steps = max(1, Int((length / max(radius / 3, 0.5)).rounded(.up)))
    var dirty = CGRect.null
    for step in 0...steps {
      let t = Double(step) / Double(steps)
      let area = stamp(
        at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), radius: radius,
        erase: erase)
      dirty = dirty.union(area)
    }
    return dirty.isNull ? .zero : dirty
  }

  private mutating func stamp(at center: CGPoint, radius: Double, erase: Bool) -> CGRect {
    let minX = max(0, Int((center.x - radius - 1).rounded(.down)))
    let maxX = min(width - 1, Int((center.x + radius + 1).rounded(.up)))
    let minY = max(0, Int((center.y - radius - 1).rounded(.down)))
    let maxY = min(height - 1, Int((center.y + radius + 1).rounded(.up)))
    guard minX <= maxX, minY <= maxY else { return .null }
    for y in minY...maxY {
      for x in minX...maxX {
        // The pixel's centre against the circle; one pixel of edge is partly covered.
        let distance = hypot(Double(x) + 0.5 - center.x, Double(y) + 0.5 - center.y)
        let cover = min(1, max(0, radius + 0.5 - distance))
        guard cover > 0 else { continue }
        let index = y * width + x
        if erase {
          pixels[index] = UInt8(Double(pixels[index]) * (1 - cover))
        } else {
          pixels[index] = max(pixels[index], UInt8((cover * 255).rounded()))
        }
      }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
  }

  public mutating func invert() {
    for index in pixels.indices { pixels[index] = 255 - pixels[index] }
  }

  public mutating func clear() {
    pixels = [UInt8](repeating: 0, count: pixels.count)
  }

  // MARK: Files

  public func pngData() -> Data? {
    guard let image = grayImage() else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }

  /// A mask read back from its PNG (any image: it is drawn in grey at the PNG's own size).
  public init?(image: CGImage) {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: width * height)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    self.width = width
    self.height = height
    pixels = bytes
  }

  func grayImage() -> CGImage? {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  // MARK: From the screen

  /// Where a point of the paint view falls in the mask. The view shows the cut `crop` (in the start
  /// image's pixels) of the image `imageWidth` pixels wide, and fills `viewSize`.
  public func point(forViewPoint point: CGPoint, viewSize: CGSize, crop: CGRect, imageWidth: Int) -> CGPoint {
    guard viewSize.width > 0, viewSize.height > 0, imageWidth > 0 else { return .zero }
    let toMask = Double(width) / Double(imageWidth)
    return CGPoint(
      x: (crop.minX + point.x / viewSize.width * crop.width) * toMask,
      y: (crop.minY + point.y / viewSize.height * crop.height) * toMask)
  }

  /// The brush's radius in mask pixels for a brush `diameter` wide in canvas pixels.
  public func brushRadius(diameter: Double, canvasWidth: Int, crop: CGRect, imageWidth: Int) -> Double {
    guard canvasWidth > 0, imageWidth > 0 else { return 0 }
    return diameter / 2 * (crop.width / Double(canvasWidth)) * (Double(width) / Double(imageWidth))
  }
}
