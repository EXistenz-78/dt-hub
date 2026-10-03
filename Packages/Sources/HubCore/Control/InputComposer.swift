import CoreGraphics
import Foundation
import HubKit

/// Prepares the Control tab's images for a RUN (tab Control spec §6).
public enum InputComposer {
  /// The start image cut and scaled to the exact canvas size, opaque. nil when the context cannot
  /// be made (a size of zero).
  /// With `paint` (the Brush drawing, in the image's own coordinates) it is put over the image in
  /// the same cut. The margins the image leaves are `fill`: its own edge pixels stretched outwards, or a
  /// flat grey or green.
  public static func frame(
    _ image: CGImage, toWidth width: Int, height: Int, framing: Framing, paint: PaintBitmap? = nil,
    fill: MarginFill = .edges
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
    switch fill {
    case .edges:
      extendEdges(of: image, drawn: drawn, in: context, width: width, height: height)
    case .gray, .green:
      context.setFillColorSpace(CGColorSpaceCreateDeviceRGB())
      context.setFillColor(fill == .gray ? [0.5, 0.5, 0.5, 1] : [0, 1, 0, 1])
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    context.draw(image, in: drawn)
    if let layer = paint?.cgImage() { context.draw(layer, in: drawn) }
    return context.makeImage()
  }

  /// Fills what the image leaves uncovered with its own edge pixels stretched outwards (and the corner
  /// pixels in the corners). The mask regenerates it anyway; this way the edge Draw Things blends
  /// back ("keep the original") carries the colours of the picture, not a stripe of grey. The corners
  /// go first, then the sides, each running one pixel under the image and into the corners, so a
  /// boundary that falls between pixels is covered whole by one strip and nothing shows through.
  private static func extendEdges(of image: CGImage, drawn: CGRect, in context: CGContext, width: Int, height: Int) {
    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
    guard !drawn.contains(canvas), image.width > 0, image.height > 0 else { return }
    let right = Double(width) - drawn.maxX
    let top = Double(height) - drawn.maxY
    let w = image.width
    let h = image.height
    func strip(_ x: Int, _ y: Int, _ cropWidth: Int, _ cropHeight: Int, into rect: CGRect) {
      guard rect.width > 0, rect.height > 0,
        let part = image.cropping(to: CGRect(x: x, y: y, width: cropWidth, height: cropHeight))
      else { return }
      context.draw(part, in: rect)
    }
    // Core Graphics counts from the bottom-left; the crops count from the top-left.
    if drawn.minX > 0 {
      if top > 0 { strip(0, 0, 1, 1, into: CGRect(x: 0, y: drawn.maxY, width: drawn.minX, height: top)) }
      if drawn.minY > 0 { strip(0, h - 1, 1, 1, into: CGRect(x: 0, y: 0, width: drawn.minX, height: drawn.minY)) }
    }
    if right > 0 {
      if top > 0 { strip(w - 1, 0, 1, 1, into: CGRect(x: drawn.maxX, y: drawn.maxY, width: right, height: top)) }
      if drawn.minY > 0 { strip(w - 1, h - 1, 1, 1, into: CGRect(x: drawn.maxX, y: 0, width: right, height: drawn.minY)) }
    }
    if drawn.minX > 0 {
      strip(0, 0, 1, h, into: CGRect(x: 0, y: drawn.minY - 1, width: drawn.minX + 1, height: drawn.height + 2))
    }
    if right > 0 {
      strip(w - 1, 0, 1, h, into: CGRect(x: drawn.maxX - 1, y: drawn.minY - 1, width: right + 1, height: drawn.height + 2))
    }
    if top > 0 {
      strip(0, 0, w, 1, into: CGRect(x: drawn.minX - 1, y: drawn.maxY - 1, width: drawn.width + 2, height: top + 1))
    }
    if drawn.minY > 0 {
      strip(0, h - 1, w, 1, into: CGRect(x: drawn.minX - 1, y: 0, width: drawn.width + 2, height: drawn.minY + 1))
    }
  }

  /// The mask for the canvas, in the same cut as the start image: transparent where the picture is
  /// regenerated, opaque where it is kept (what the client wants). The mask is scaled with the same
  /// smoothing as the image and then cut at half, so its edge is clean at any scale. What the image
  /// does not cover (its margins in the canvas) is regenerated too, unless `marginsRegenerated` is false
  /// (a flat fill that an outpaint LoRA reads: the margins stay out of the mask); with no `mask` and the
  /// margins regenerated that is all.
  public static func mask(
    _ mask: MaskBitmap?, imageWidth: Int, imageHeight: Int, toWidth width: Int, height: Int, framing: Framing,
    marginsRegenerated: Bool = true
  ) -> CGImage? {
    guard width > 0, height > 0, imageWidth > 0, imageHeight > 0 else { return nil }
    var gray: CGImage?
    if let mask {
      gray = mask.grayImage()
      if gray == nil { return nil }
    }
    let crop = FramingMath.cropRect(
      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: width, canvasHeight: height, framing: framing)
    var bytes = [UInt8](repeating: marginsRegenerated ? 255 : 0, count: width * height)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      context.interpolationQuality = .high
      let scale = Double(width) / crop.width
      // Where the image is: kept, unless the mask says otherwise.
      let drawn = CGRect(
        x: -crop.minX * scale, y: -(Double(imageHeight) - crop.maxY) * scale, width: Double(imageWidth) * scale,
        height: Double(imageHeight) * scale)
      context.setFillColor(gray: 0, alpha: 1)
      context.fill(drawn)
      if let gray { context.draw(gray, in: drawn) }
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
