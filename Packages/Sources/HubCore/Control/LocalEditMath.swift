import CoreGraphics
import HubKit

/// The arithmetic of local editing: turns the rectangle drawn on the start image
/// into the crop actually taken, and sizes the soft edge used when putting it back.
public enum LocalEditMath {
  /// Shortest side of a crop.
  public static let minSide = 512
  /// Longest side of a crop.
  public static let maxSide = 4096
  /// Sides are multiples of this.
  public static let step = 64

  /// The crop for a drawn rectangle: sides multiples of 64 in 512...4096, centred on the
  /// drawing, always inside the image. Nil if the image is too small or the drawing misses it.
  public static func snapped(_ drawn: CGRect, imageWidth: Int, imageHeight: Int) -> PixelRect? {
    guard imageWidth >= minSide, imageHeight >= minSide else { return nil }
    let clipped = drawn.standardized.intersection(
      CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
    let (x, width) = axis(origin: clipped.minX, length: clipped.width, imageSide: imageWidth)
    let (y, height) = axis(origin: clipped.minY, length: clipped.height, imageSide: imageHeight)
    return PixelRect(x: x, y: y, width: width, height: height)
  }

  /// Width in pixels of the soft edge: 3% of the short side, at least 8.
  public static func featherWidth(for rect: PixelRect) -> Int {
    max(8, Int((0.03 * Double(min(rect.width, rect.height))).rounded(.down)))
  }

  /// Side and position along one axis.
  private static func axis(origin: CGFloat, length: CGFloat, imageSide: Int) -> (Int, Int) {
    let up = Int((length / CGFloat(step)).rounded(.up)) * step
    let fits = imageSide / step * step
    let side = min(fits, min(maxSide, max(minSide, up)))
    let centre = origin + length / 2
    let position = Int((centre - CGFloat(side) / 2).rounded(.down))
    return (min(max(position, 0), imageSide - side), side)
  }
}
