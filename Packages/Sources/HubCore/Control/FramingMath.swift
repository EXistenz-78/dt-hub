import CoreGraphics
import Foundation
import HubKit

/// A width and a height in pixels.
public struct Size: Equatable, Sendable {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }
}

/// How a start image is cut to fill the canvas, and what that costs (tab Control spec §5).
public enum FramingMath {
  public enum Axis: Equatable, Sendable {
    case horizontal
    case vertical
  }

  /// What the zoom does to the window: +100 shows a quarter of the fill window (the image is 4 times
  /// larger), −100 shows 4 times more (the image is a quarter of the size). Exponential, so the same
  /// distance on the slider has the same effect on both sides of 0.
  public static func factor(zoom: Double) -> Double {
    pow(4, min(100, max(-100, zoom)) / 100)
  }

  /// The window of the fill (zoom 0) in image pixels: the whole image on the axis that fits, a cut on
  /// the other.
  private static func fillSize(imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int) -> (
    width: Double, height: Double
  ) {
    let iw = Double(imageWidth)
    let ih = Double(imageHeight)
    let canvasRatio = Double(canvasWidth) / Double(max(canvasHeight, 1))
    let imageRatio = iw / max(ih, 1)
    if imageRatio > canvasRatio { return (ih * canvasRatio, ih) }
    if imageRatio < canvasRatio { return (iw, iw / canvasRatio) }
    return (iw, ih)
  }

  /// The window on the image, in its pixels counted from the top-left, that fills the canvas: the fill
  /// window divided by the zoom factor, placed by the offset. It can be larger than the image (the
  /// part outside is margin) and then the offset puts the image against the start (-1), the centre
  /// (0) or the end (1) of the canvas.
  public static func cropRect(
    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int, framing: Framing
  ) -> CGRect {
    let fill = fillSize(
      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
    let framing = framing.clamped()
    let factor = factor(zoom: framing.zoom)
    let width = fill.width / factor
    let height = fill.height / factor
    return CGRect(
      x: (Double(imageWidth) - width) * (1 + framing.offsetX) / 2,
      y: (Double(imageHeight) - height) * (1 + framing.offsetY) / 2, width: width, height: height)
  }

  /// The margins around the image in the canvas, in canvas pixels.
  public struct Margins: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    /// A margin under half a pixel is rounding, not margin.
    public var isEmpty: Bool { max(left, top, right, bottom) < 0.5 }
  }

  public static func margins(
    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int, framing: Framing
  ) -> Margins {
    let crop = cropRect(
      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
      framing: framing)
    let scale = Double(canvasWidth) / crop.width
    return Margins(
      left: max(0, -crop.minX) * scale, top: max(0, -crop.minY) * scale,
      right: max(0, crop.maxX - Double(imageWidth)) * scale, bottom: max(0, crop.maxY - Double(imageHeight)) * scale)
  }

  /// The zoom (0 or less) at which the whole image just fits in the canvas.
  public static func zoomContain(imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int) -> Double {
    let across = Double(canvasWidth) / Double(max(imageWidth, 1))
    let down = Double(canvasHeight) / Double(max(imageHeight, 1))
    return 100 * log(min(across, down) / max(across, down)) / log(4)
  }

  /// The share (0…1) of the image's area that is inside the window.
  public static func usedShare(
    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int, framing: Framing
  ) -> Double {
    let crop = cropRect(
      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
      framing: framing)
    let inside = crop.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    return inside.isNull ? 0 : inside.width * inside.height / (Double(imageWidth) * Double(imageHeight))
  }

  /// The share of the image that falls outside the canvas, and on which axis (nil when none). With a
  /// `zoom` the window is the one of that zoom.
  public static func loss(
    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int, zoom: Double = 0
  ) -> (axis: Axis?, fraction: Double) {
    let rect = cropRect(
      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
      framing: Framing(zoom: zoom))
    let horizontal = 1 - rect.width / Double(imageWidth)
    let vertical = 1 - rect.height / Double(imageHeight)
    if horizontal > 0.000_001 { return (.horizontal, horizontal) }
    if vertical > 0.000_001 { return (.vertical, vertical) }
    return (nil, 0)
  }

  /// "Adapt the dimensions": the image's ratio, the area of the current canvas, both sides
  /// multiples of 64 and within 64…`limit`.
  public static func adaptedSize(
    imageWidth: Int, imageHeight: Int, currentWidth: Int, currentHeight: Int,
    limit: Int = GenerationParameters.sizeRange.upperBound
  ) -> Size {
    let ratio = Double(imageWidth) / Double(max(imageHeight, 1))
    let area = Double(currentWidth * currentHeight)
    let height = (area / ratio).squareRoot()
    let width = ratio * height
    func snap(_ value: Double) -> Int { min(max(Int((value / 64).rounded()) * 64, 64), limit) }
    return Size(width: snap(width), height: snap(height))
  }
}
