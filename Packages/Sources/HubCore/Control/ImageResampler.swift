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

  /// `image` at `width × height`; nil for a size of zero or when the picture cannot be made.
  static func scaled(_ image: CGImage, toWidth width: Int, height: Int, with method: Resampling) -> CGImage? {
    guard width > 0, height > 0, image.width > 0, image.height > 0 else { return nil }
    if method == .coreGraphics { return coreGraphics(image, width: width, height: height) }
    let sx = Double(width) / Double(image.width)
    let sy = Double(height) / Double(image.height)
    // The edges are repeated outwards so the filters do not fade them into transparent black.
    let source = CIImage(cgImage: image).clampedToExtent()
    let output: CIImage?
    switch method {
    case .coreGraphics: return nil
    case .catmullRom: output = bicubic(source, sx: sx, sy: sy, b: 0, c: 0.5)
    case .mitchell: output = bicubic(source, sx: sx, sy: sy, b: 1.0 / 3, c: 1.0 / 3)
    case .bSpline: output = bicubic(source, sx: sx, sy: sy, b: 1, c: 0)
    case .lanczos:
      let filter = CIFilter(name: "CILanczosScaleTransform")
      filter?.setValue(source, forKey: kCIInputImageKey)
      filter?.setValue(sy, forKey: kCIInputScaleKey)
      filter?.setValue(sx / sy, forKey: kCIInputAspectRatioKey)
      output = filter?.outputImage
    case .bilinear: output = source.samplingLinear().transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    case .nearest: output = source.samplingNearest().transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    }
    guard let output else { return nil }
    return makeContext().createCGImage(
      output, from: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB())
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
