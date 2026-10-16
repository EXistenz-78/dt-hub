import CoreGraphics
import Foundation

/// The crop of one person that goes to the whole-body model: an area of the picture around the person's box, with the
/// 288:384 ratio of the model input, scaled uniformly to 288×384. The numbers are those of rtmlib's top-down affine
/// (padding 1.25): a uniform scale and a translation that sends the centre of the area to the centre of the crop.
struct DPCrop: Equatable, Sendable {
  static let width = 288
  static let height = 384

  /// The centre of the box, in pixels of the picture (origin at the top left).
  let center: CGPoint
  /// The size, in pixels of the picture, of the area the crop shows.
  let scale: CGSize

  /// `box` is in pixels of the picture, origin at the top left. The area is the box times `padding`, widened on the
  /// shorter side to the ratio of the model input.
  init(box: CGRect, padding: Double = 1.25) {
    center = CGPoint(x: box.midX, y: box.midY)
    var width = max(1, Double(box.width) * padding)
    var height = max(1, Double(box.height) * padding)
    let aspect = Double(Self.width) / Double(Self.height)
    if width > height * aspect { height = width / aspect } else { width = height * aspect }
    scale = CGSize(width: width, height: height)
  }

  /// Crop pixels per picture pixel.
  var factor: Double { Double(Self.width) / Double(scale.width) }

  /// Where the picture's origin lands in the crop.
  var translation: CGPoint {
    CGPoint(x: Double(Self.width) / 2 - factor * Double(center.x), y: Double(Self.height) / 2 - factor * Double(center.y))
  }

  /// The point of the picture a SimCC bin stands for (two bins per crop pixel).
  func imagePoint(binX: Double, binY: Double) -> CGPoint {
    CGPoint(
      x: binX / 2 / Double(Self.width) * Double(scale.width) + Double(center.x) - Double(scale.width) / 2,
      y: binY / 2 / Double(Self.height) * Double(scale.height) + Double(center.y) - Double(scale.height) / 2)
  }

  /// The crop as a 288×384 RGB picture; black where the area leaves the picture.
  func render(_ image: CGImage) -> CGImage? {
    guard
      let context = CGContext(
        data: nil, width: Self.width, height: Self.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
    context.interpolationQuality = .high
    // Work with the origin at the top left, like the points.
    context.translateBy(x: 0, y: CGFloat(Self.height))
    context.scaleBy(x: 1, y: -1)
    context.translateBy(x: translation.x, y: translation.y)
    context.scaleBy(x: CGFloat(factor), y: CGFloat(factor))
    // CoreGraphics draws an image upright in a y-up space: turn it back for the y-down one.
    context.translateBy(x: 0, y: CGFloat(image.height))
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
  }
}
