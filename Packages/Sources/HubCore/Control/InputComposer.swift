import CoreGraphics
import HubKit

/// Prepares the Control tab's images for a RUN (tab Control spec §6).
public enum InputComposer {
  /// The start image cut and scaled to the exact canvas size, opaque. nil when the context cannot
  /// be made (a size of zero).
  public static func frame(_ image: CGImage, toWidth width: Int, height: Int, framing: Framing) -> CGImage? {
    guard width > 0, height > 0 else { return nil }
    let crop = FramingMath.cropRect(
      imageWidth: image.width, imageHeight: image.height, canvasWidth: width, canvasHeight: height, framing: framing)
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    // The image drawn so that the cut fills the canvas (Core Graphics counts from the bottom-left).
    let scale = Double(width) / crop.width
    let drawn = CGRect(
      x: -crop.minX * scale, y: -(Double(image.height) - crop.maxY) * scale,
      width: Double(image.width) * scale, height: Double(image.height) * scale)
    context.draw(image, in: drawn)
    return context.makeImage()
  }
}
