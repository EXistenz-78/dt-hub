import CoreGraphics
import Foundation

/// The mask as a translucent colour over the picture, for the screen. It is kept between strokes
/// and only the pixels a stroke touched are rewritten (`update`), so painting stays fluent: the
/// whole picture is rebuilt only when a mask is read (`rebuild`).
public final class MaskOverlay {
  public let width: Int
  public let height: Int
  private let context: CGContext
  private let red: Double
  private let green: Double
  private let blue: Double
  private let opacity: Double

  public init?(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8, opacity: Double) {
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    self.width = width
    self.height = height
    self.context = context
    self.red = Double(red)
    self.green = Double(green)
    self.blue = Double(blue)
    self.opacity = opacity
  }

  /// Rewrites the whole overlay from the mask (which must have the overlay's size).
  public func rebuild(from mask: MaskBitmap) {
    update(from: mask, rect: CGRect(x: 0, y: 0, width: width, height: height))
  }

  /// Rewrites the pixels inside `rect` (mask pixels) from the mask.
  public func update(from mask: MaskBitmap, rect: CGRect) {
    guard mask.width == width, mask.height == height, let data = context.data else { return }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    let minX = max(0, Int(rect.minX.rounded(.down)))
    let maxX = min(width, Int(rect.maxX.rounded(.up)))
    let minY = max(0, Int(rect.minY.rounded(.down)))
    let maxY = min(height, Int(rect.maxY.rounded(.up)))
    guard minX < maxX, minY < maxY else { return }
    for y in minY..<maxY {
      for x in minX..<maxX {
        let value = mask.pixels[y * width + x]
        let base = (y * width + x) * 4
        if value == 0 {
          bytes[base] = 0
          bytes[base + 1] = 0
          bytes[base + 2] = 0
          bytes[base + 3] = 0
        } else {
          let alpha = Double(value) / 255 * opacity
          bytes[base] = UInt8((red * alpha).rounded())
          bytes[base + 1] = UInt8((green * alpha).rounded())
          bytes[base + 2] = UInt8((blue * alpha).rounded())
          bytes[base + 3] = UInt8((alpha * 255).rounded())
        }
      }
    }
  }

  /// A snapshot of the overlay as it is now.
  public func image() -> CGImage? { context.makeImage() }
}
