import CoreGraphics
import Foundation

/// The Brush drawing as an image for the screen, kept between strokes: only the pixels a stroke
/// touched are rewritten (`update`), the whole picture is rebuilt only when a drawing is read.
public final class PaintOverlay {
  public let width: Int
  public let height: Int
  private let context: CGContext

  public init?(width: Int, height: Int) {
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    self.width = width
    self.height = height
    self.context = context
  }

  public func rebuild(from paint: PaintBitmap) {
    update(from: paint, rect: CGRect(x: 0, y: 0, width: width, height: height))
  }

  /// Rewrites the pixels inside `rect` (layer pixels) from the drawing (which must have the overlay's size).
  public func update(from paint: PaintBitmap, rect: CGRect) {
    guard paint.width == width, paint.height == height, let data = context.data else { return }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    let minX = max(0, Int(rect.minX.rounded(.down)))
    let maxX = min(width, Int(rect.maxX.rounded(.up)))
    let minY = max(0, Int(rect.minY.rounded(.down)))
    let maxY = min(height, Int(rect.maxY.rounded(.up)))
    guard minX < maxX, minY < maxY else { return }
    for y in minY..<maxY {
      for x in minX..<maxX {
        let base = (y * width + x) * 4
        let alpha = Int(paint.pixels[base + 3])
        // Premultiplied for the screen.
        bytes[base] = UInt8((Int(paint.pixels[base]) * alpha + 127) / 255)
        bytes[base + 1] = UInt8((Int(paint.pixels[base + 1]) * alpha + 127) / 255)
        bytes[base + 2] = UInt8((Int(paint.pixels[base + 2]) * alpha + 127) / 255)
        bytes[base + 3] = UInt8(alpha)
      }
    }
  }

  public func image() -> CGImage? { context.makeImage() }
}
