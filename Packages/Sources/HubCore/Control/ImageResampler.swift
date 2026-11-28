import CoreGraphics
import CoreImage
import Foundation
import HubKit

/// Scales a picture with a chosen algorithm (`2026-11-28-ingrandimento-immagine-partenza-design.md`). Core Graphics is
/// what DT Hub always did; the others go through Core Image, without colour management, so the bytes are scaled as
/// they are (measured: Catmull-Rom matches PIL's bicubic within 0.16 of 255 on average).
enum ImageResampler {
  /// A context per call: with one shared context, concurrent renders mixed up their sampling (a nearest scale came
  /// out bilinear while another render ran). A RUN scales one picture, so the cost does not matter.
  private static func makeContext() -> CIContext {
    CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])
  }

  /// `image` at `width × height`; nil for a size of zero or when the picture cannot be made. With `region` (in the
  /// scaled picture's pixels, from its bottom-left) only that part is made, as it would be in the whole picture.
  static func scaled(
    _ image: CGImage, toWidth width: Int, height: Int, with method: Resampling, region: CGRect? = nil
  ) -> CGImage? {
    guard width > 0, height > 0, image.width > 0, image.height > 0 else { return nil }
    if method == .coreGraphics {  // the tests' reference; InputComposer draws Core Graphics itself
      return coreGraphics(image, width: width, height: height)
    }
    // Core Image passes the bytes through untouched; a picture in another colour space (a Display P3 or Adobe RGB
    // photo) is first converted the way the Core Graphics path converts it, so the algorithm changes texture, not colour.
    guard let source = deviceRGB(image) else { return nil }
    let picture = CIImage(cgImage: source).clampedToExtent()  // edges repeated, not faded into transparent black
    let sx = Double(width) / Double(image.width)
    let sy = Double(height) / Double(image.height)
    let output: CIImage?
    switch method {
    case .coreGraphics: return nil
    case .catmullRom: output = bicubic(picture, sx: sx, sy: sy, b: 0, c: 0.5)
    case .mitchell: output = bicubic(picture, sx: sx, sy: sy, b: 1.0 / 3, c: 1.0 / 3)
    case .bSpline: output = bicubic(picture, sx: sx, sy: sy, b: 1, c: 0)
    case .lanczos:
      let filter = CIFilter(name: "CILanczosScaleTransform")
      filter?.setValue(picture, forKey: kCIInputImageKey)
      filter?.setValue(sy, forKey: kCIInputScaleKey)
      filter?.setValue(sx / sy, forKey: kCIInputAspectRatioKey)
      output = filter?.outputImage
    case .bilinear: output = picture.samplingLinear().transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    case .nearest: output = picture.samplingNearest().transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    }
    guard let output else { return nil }
    let wanted = (region ?? CGRect(x: 0, y: 0, width: width, height: height)).integral
    guard wanted.width > 0, wanted.height > 0 else { return nil }
    return makeContext().createCGImage(output, from: wanted, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
  }

  /// The picture as it is when it is in sRGB or device RGB; otherwise redrawn at its size into device RGB.
  private static func deviceRGB(_ image: CGImage) -> CGImage? {
    let space = image.colorSpace
    if space == nil || space?.name == CGColorSpace.sRGB || space == CGColorSpaceCreateDeviceRGB() { return image }
    guard
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
  }

  private static func bicubic(_ source: CIImage, sx: Double, sy: Double, b: Double, c: Double) -> CIImage? {
    let filter = CIFilter(name: "CIBicubicScaleTransform")
    filter?.setValue(source, forKey: kCIInputImageKey)
    filter?.setValue(sy, forKey: kCIInputScaleKey)
    filter?.setValue(sx / sy, forKey: kCIInputAspectRatioKey)
    filter?.setValue(b, forKey: "inputB")
    filter?.setValue(c, forKey: "inputC")
    return filter?.outputImage
  }

  private static func coreGraphics(_ image: CGImage, width: Int, height: Int) -> CGImage? {
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }
}
