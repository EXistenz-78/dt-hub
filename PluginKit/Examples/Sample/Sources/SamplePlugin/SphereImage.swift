import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A lit sphere on a dark ground, as a PNG: the picture a lighting plug-in would hand to the Moodboard.
enum SphereImage {
  /// `azimuth` is the direction the light comes from, in degrees (0 = right, 90 = above).
  static func png(azimuth: Double, size: Int = 512) -> Data? {
    guard
      let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let side = CGFloat(size)
    context.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let center = CGPoint(x: side / 2, y: side / 2)
    let radius = side * 0.38
    let angle = azimuth * .pi / 180
    let highlight = CGPoint(x: center.x + CGFloat(cos(angle)) * radius * 0.55, y: center.y + CGFloat(sin(angle)) * radius * 0.55)
    let colors = [CGColor(red: 1, green: 0.97, blue: 0.9, alpha: 1), CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)]
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])
    else { return nil }
    context.saveGState()
    context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    context.clip()
    context.drawRadialGradient(
      gradient, startCenter: highlight, startRadius: 0, endCenter: highlight, endRadius: radius * 1.6, options: [])
    context.restoreGState()
    guard let image = context.makeImage() else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }
}
