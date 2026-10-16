import CoreGraphics
import Foundation

enum DPDepthError: Error, Equatable {
  case cannotResize
  case noDepthOutput
  case unsupportedOutput(UInt32)
}

/// A depth model: a picture at the size it asks for in, a grey picture (any size) out. Higher is nearer.
protocol DPDepthModel: Sendable {
  func predict(_ image: CGImage) throws -> CGImage
}

/// Turns a picture into its depth map: near is bright, far is dark, 0–255 over the whole picture, at the size of the
/// picture.
struct DepthEstimator {
  var model: any DPDepthModel
  /// Set when the model gives far as bright (the live test decides; Depth Anything gives near as bright).
  var invertsModelOutput = false

  /// Short side 518 pixels (what the model asks for), long side a multiple of 14, at most 2072 so a panorama does not
  /// ask for gigabytes.
  static func inputSize(forWidth width: Int, height: Int) -> (width: Int, height: Int) {
    let shortSide = 518.0, step = 14.0, maxLong = 2072.0
    let short = Double(min(width, height)), long = Double(max(width, height))
    let scaledLong = min(maxLong, max(step, (long * shortSide / short / step).rounded() * step))
    return width >= height ? (Int(scaledLong), Int(shortSide)) : (Int(shortSide), Int(scaledLong))
  }

  func depthMap(for image: CGImage) throws -> CGImage {
    var source = image
    let longSide = max(image.width, image.height)
    if longSide > DPImage.maxLongSide {
      let scale = Double(DPImage.maxLongSide) / Double(longSide)
      guard
        let reduced = DPImage.resized(
          image, width: max(1, Int((Double(image.width) * scale).rounded())),
          height: max(1, Int((Double(image.height) * scale).rounded())))
      else { throw DPDepthError.cannotResize }
      source = reduced
    }
    let size = Self.inputSize(forWidth: source.width, height: source.height)
    guard let input = DPImage.resized(source, width: size.width, height: size.height) else {
      throw DPDepthError.cannotResize
    }
    let output = try model.predict(input)
    return try Self.normalised(output, width: source.width, height: source.height, inverted: invertsModelOutput)
  }

  /// The model's picture at the size of the source, stretched to the whole 0–255 range.
  private static func normalised(_ output: CGImage, width: Int, height: Int, inverted: Bool) throws -> CGImage {
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
      let data = context.data
    else { throw DPDepthError.cannotResize }
    context.interpolationQuality = .high
    context.draw(output, in: CGRect(x: 0, y: 0, width: width, height: height))
    let rows = data.assumingMemoryBound(to: UInt8.self)
    let stride = context.bytesPerRow
    var low = UInt8.max, high = UInt8.min
    for y in 0..<height {
      for x in 0..<width {
        let v = rows[y * stride + x]
        low = min(low, v)
        high = max(high, v)
      }
    }
    var bytes = [UInt8](repeating: 0, count: width * height)
    if high > low {
      let range = Double(high - low)
      for y in 0..<height {
        for x in 0..<width {
          var v = (Double(rows[y * stride + x] - low) / range * 255).rounded()
          if inverted { v = 255 - v }
          bytes[y * width + x] = UInt8(v)
        }
      }
    } else if inverted {
      bytes = [UInt8](repeating: 255, count: width * height)
    }
    guard
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: true,
        intent: .defaultIntent)
    else { throw DPDepthError.cannotResize }
    return image
  }
}
