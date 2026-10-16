import CoreGraphics
import Foundation

enum DPDepthError: Error, Equatable {
  case cannotResize
  case noDepthOutput
  case unsupportedOutput(UInt32)
}

/// A depth model: a picture of exactly `inputSize` in, a grey picture (any size) out. Higher is nearer.
protocol DPDepthModel: Sendable {
  var inputSize: (width: Int, height: Int) { get }
  func predict(_ image: CGImage) throws -> CGImage
}

/// Turns a picture into its depth map: near is bright, far is dark, 0–255 over the whole picture, at the size of the
/// picture (reduced to 2048 px on the long side).
struct DepthEstimator: Sendable {
  var model: any DPDepthModel
  /// Set when the model gives far as bright (the live test decides; Depth Anything gives near as bright).
  var invertsModelOutput = false

  /// Where a picture goes inside the model input: as large as fits, proportions kept, centred. Whatever is left of the
  /// input is padding (black), cropped away from the answer.
  struct Fit: Equatable, Sendable {
    var width: Int
    var height: Int
    var x: Int
    var y: Int
  }

  static func fit(width: Int, height: Int, into input: (width: Int, height: Int)) -> Fit {
    let scale = min(Double(input.width) / Double(width), Double(input.height) / Double(height))
    let fitWidth = min(input.width, max(1, Int((Double(width) * scale).rounded())))
    let fitHeight = min(input.height, max(1, Int((Double(height) * scale).rounded())))
    return Fit(width: fitWidth, height: fitHeight, x: (input.width - fitWidth) / 2, y: (input.height - fitHeight) / 2)
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
    let input = model.inputSize
    let place = Self.fit(width: source.width, height: source.height, into: input)
    guard let padded = Self.padded(source, into: input, at: place) else { throw DPDepthError.cannotResize }
    let output = try model.predict(padded)
    // The part of the answer that belongs to the picture, in the pixels of the answer.
    let sx = Double(output.width) / Double(input.width), sy = Double(output.height) / Double(input.height)
    let region = CGRect(
      x: Double(place.x) * sx, y: Double(place.y) * sy, width: Double(place.width) * sx, height: Double(place.height) * sy)
    return try Self.normalised(
      output, region: region, width: source.width, height: source.height, inverted: invertsModelOutput)
  }

  /// The picture on a black canvas of the model's size, at `place`.
  private static func padded(_ image: CGImage, into input: (width: Int, height: Int), at place: Fit) -> CGImage? {
    guard
      let context = CGContext(
        data: nil, width: input.width, height: input.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: input.width, height: input.height))
    context.interpolationQuality = .high
    context.draw(
      image,
      in: CGRect(x: place.x, y: input.height - place.y - place.height, width: place.width, height: place.height))
    return context.makeImage()
  }

  /// `region` of the model's picture (pixels of the answer, origin at the top left) at the size of the source,
  /// stretched to the whole 0–255 range.
  private static func normalised(
    _ output: CGImage, region: CGRect, width: Int, height: Int, inverted: Bool
  ) throws -> CGImage {
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
      let data = context.data
    else { throw DPDepthError.cannotResize }
    context.interpolationQuality = .high
    // Cut the padding away first, so the smoothing at the edges only ever sees the picture's own pixels.
    let x0 = Int(region.minX.rounded()), y0 = Int(region.minY.rounded())
    let cut = CGRect(
      x: x0, y: y0, width: max(1, Int(region.maxX.rounded()) - x0), height: max(1, Int(region.maxY.rounded()) - y0))
    guard let content = output.cropping(to: cut) else { throw DPDepthError.cannotResize }
    context.draw(content, in: CGRect(x: 0, y: 0, width: width, height: height))
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
