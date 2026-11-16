import CoreGraphics
import HubKit

/// Where the start image sits in the Local Editing stage, and the conversion between the view's
/// points and the image's pixels (origin top left, y down in both).
public struct LocalEditViewMath: Equatable, Sendable {
  public let imageWidth: Int
  public let imageHeight: Int
  /// The picture fitted in the view, centred (letterboxed when the ratios differ).
  public let imageFrame: CGRect

  public init(imageWidth: Int, imageHeight: Int, viewSize: CGSize) {
    self.imageWidth = imageWidth
    self.imageHeight = imageHeight
    let fit = min(
      viewSize.width / CGFloat(max(imageWidth, 1)), viewSize.height / CGFloat(max(imageHeight, 1)))
    let size = CGSize(width: CGFloat(imageWidth) * fit, height: CGFloat(imageHeight) * fit)
    imageFrame = CGRect(
      x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2, width: size.width,
      height: size.height)
  }

  /// Pixels per point.
  private var pixelsPerPoint: CGFloat {
    imageFrame.width > 0 ? CGFloat(imageWidth) / imageFrame.width : 0
  }

  /// The pixel under a point of the view, kept inside the image.
  public func pixel(at point: CGPoint) -> CGPoint {
    let x = (point.x - imageFrame.minX) * pixelsPerPoint
    let y = (point.y - imageFrame.minY) * pixelsPerPoint
    return CGPoint(
      x: min(max(x, 0), CGFloat(imageWidth)), y: min(max(y, 0), CGFloat(imageHeight)))
  }

  /// The rectangle of pixels between two points of the view, in any order.
  public func pixelRect(from start: CGPoint, to end: CGPoint) -> CGRect {
    let a = pixel(at: start), b = pixel(at: end)
    return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }

  /// Where a rectangle of pixels shows in the view.
  public func viewRect(of rect: PixelRect) -> CGRect {
    let scale = pixelsPerPoint > 0 ? 1 / pixelsPerPoint : 0
    return CGRect(
      x: imageFrame.minX + CGFloat(rect.x) * scale, y: imageFrame.minY + CGFloat(rect.y) * scale,
      width: CGFloat(rect.width) * scale, height: CGFloat(rect.height) * scale)
  }

  /// `rect` of an image `fromWidth × fromHeight` on the same image reduced to `toWidth × toHeight`
  /// (the preview): edges rounded to the nearest pixel, kept inside.
  public static func scaled(
    _ rect: PixelRect, fromWidth: Int, fromHeight: Int, toWidth: Int, toHeight: Int
  ) -> PixelRect {
    let sx = Double(toWidth) / Double(max(fromWidth, 1))
    let sy = Double(toHeight) / Double(max(fromHeight, 1))
    let x0 = min(max(Int((Double(rect.x) * sx).rounded()), 0), toWidth)
    let y0 = min(max(Int((Double(rect.y) * sy).rounded()), 0), toHeight)
    let x1 = min(max(Int((Double(rect.x + rect.width) * sx).rounded()), x0), toWidth)
    let y1 = min(max(Int((Double(rect.y + rect.height) * sy).rounded()), y0), toHeight)
    return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }
}
