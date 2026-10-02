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

  /// The part of the image, in its pixels counted from the top-left, that fills the canvas
  /// ("fill"): the whole image on the axis that fits, a cut on the other, placed by the offset.
  public static func cropRect(
    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int, framing: Framing
  ) -> CGRect {
    let iw = Double(imageWidth)
    let ih = Double(imageHeight)
    let canvasRatio = Double(canvasWidth) / Double(max(canvasHeight, 1))
    let imageRatio = iw / max(ih, 1)
    let offset = framing.clamped()
    if imageRatio > canvasRatio {
      let width = ih * canvasRatio
      return CGRect(x: (iw - width) * (1 + offset.offsetX) / 2, y: 0, width: width, height: ih)
    }
    if imageRatio < canvasRatio {
      let height = iw / canvasRatio
      return CGRect(x: 0, y: (ih - height) * (1 + offset.offsetY) / 2, width: iw, height: height)
    }
    return CGRect(x: 0, y: 0, width: iw, height: ih)
  }

  /// The share of the image that falls outside the canvas, and on which axis (nil when none).
  public static func loss(
    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int
  ) -> (axis: Axis?, fraction: Double) {
    let rect = cropRect(
      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
      framing: Framing())
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
