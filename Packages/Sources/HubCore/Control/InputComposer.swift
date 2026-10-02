import CoreGraphics
import Foundation
import HubKit

/// Prepares the Control tab's images for a RUN (tab Control spec §6).
public enum InputComposer {
  /// The start image cut and scaled to the exact canvas size, opaque. nil when the context cannot
  /// be made (a size of zero).
  /// With `paint` (the Brush drawing, in the image's own coordinates) it is put over the image in
  /// the same cut.
  public static func frame(
    _ image: CGImage, toWidth width: Int, height: Int, framing: Framing, paint: PaintBitmap? = nil
  ) -> CGImage? {
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
    if let layer = paint?.cgImage() { context.draw(layer, in: drawn) }
    return context.makeImage()
  }

  /// The mask for the canvas, in the same cut as the start image: transparent where the picture is
  /// regenerated, opaque where it is kept (what the client wants). The mask is scaled with the same
  /// smoothing as the image and then cut at half, so its edge is clean at any scale.
  public static func mask(
    _ mask: MaskBitmap, imageWidth: Int, imageHeight: Int, toWidth width: Int, height: Int, framing: Framing
  ) -> CGImage? {
    guard width > 0, height > 0, imageWidth > 0, imageHeight > 0, let gray = mask.grayImage() else { return nil }
    let crop = FramingMath.cropRect(
      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: width, canvasHeight: height, framing: framing)
    var bytes = [UInt8](repeating: 0, count: width * height)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      context.interpolationQuality = .high
      let scale = Double(width) / crop.width
      context.draw(
        gray,
        in: CGRect(
          x: -crop.minX * scale, y: -(Double(imageHeight) - crop.maxY) * scale, width: Double(imageWidth) * scale,
          height: Double(imageHeight) * scale))
      return true
    }
    guard drawn else { return nil }
    // Transparent (0) where regenerated; black, premultiplied, so the colour channels stay 0.
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    for index in bytes.indices where bytes[index] < 128 { rgba[index * 4 + 3] = 255 }
    guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }
}
