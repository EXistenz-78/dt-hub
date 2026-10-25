import CoreGraphics
import Foundation

/// One picture to put on the panorama, in its place: the frame it looks along and how opaque it is.
struct PSLayer: @unchecked Sendable {
  var image: CGImage
  var basis: StickerBasis
  var opacity: Double
}

enum PSRenderError: Error, Equatable {
  case metal(String)
  case image
}

/// Draws the panorama: the layers in order (the first is the bottom one) over `#00ff00`, as a `width × height` equirectangular picture.
/// `uOffset` rolls the picture sideways, in turns.
protocol PSRendering: Sendable {
  func render(_ layers: [PSLayer], width: Int, height: Int, uOffset: Double) throws -> CGImage
}

/// Pictures as bytes: premultiplied RGBA, 8 bits, sRGB, the first row on top.
enum PSPixels {
  static func rgba(of image: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return (bytes, width, height)
  }

  /// An opaque picture from RGBA bytes (alpha is taken as 255).
  static func image(bytes: [UInt8], width: Int, height: Int) -> CGImage? {
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
      shouldInterpolate: true, intent: .defaultIntent)
  }
}

private struct Box: @unchecked Sendable { let pointer: UnsafeMutablePointer<UInt8> }

/// The reference renderer: every pixel's ray against every layer, bilinear, premultiplied alpha, rows on all cores. The Metal renderer
/// must agree with it; it also takes over when Metal cannot be used.
final class PSCPURenderer: PSRendering {
  private struct Prepared: Sendable {
    var bytes: [UInt8]
    var width: Int
    var height: Int
    var basis: StickerBasis
    var opacity: Double
  }

  func render(_ layers: [PSLayer], width: Int, height: Int, uOffset: Double) throws -> CGImage {
    let prepared = layers.map { layer -> Prepared in
      let pixels = PSPixels.rgba(of: layer.image)
      return Prepared(bytes: pixels.bytes, width: pixels.width, height: pixels.height, basis: layer.basis, opacity: layer.opacity)
    }
    let sinLon = (0..<width).map { sin((((Double($0) + 0.5) / Double(width)) + uOffset - 0.5) * 2 * .pi) }
    let cosLon = (0..<width).map { cos((((Double($0) + 0.5) / Double(width)) + uOffset - 0.5) * 2 * .pi) }
    var output = [UInt8](repeating: 255, count: width * height * 4)
    output.withUnsafeMutableBufferPointer { buffer in
      let box = Box(pointer: buffer.baseAddress!)
      DispatchQueue.concurrentPerform(iterations: height) { y in
        let lat = (0.5 - (Double(y) + 0.5) / Double(height)) * .pi
        let cl = cos(lat), sl = sin(lat)
        for x in 0..<width {
          let d = Vec3(x: sinLon[x] * cl, y: sl, z: cosLon[x] * cl)
          var r = 0.0, g = 1.0, b = 0.0
          for layer in prepared {
            let dz = d.dot(layer.basis.forward)
            guard dz > 1e-5 else { continue }
            let s = d.dot(layer.basis.right) / dz / layer.basis.tanX * 0.5 + 0.5
            let t = 0.5 - d.dot(layer.basis.up) / dz / layer.basis.tanY * 0.5
            guard s >= 0, s <= 1, t >= 0, t <= 1 else { continue }
            let c = Self.sample(layer, s: s, t: t)
            let k = 1 - c.a * layer.opacity
            r = c.r * layer.opacity + r * k
            g = c.g * layer.opacity + g * k
            b = c.b * layer.opacity + b * k
          }
          let i = (y * width + x) * 4
          box.pointer[i] = UInt8((min(1, max(0, r)) * 255).rounded())
          box.pointer[i + 1] = UInt8((min(1, max(0, g)) * 255).rounded())
          box.pointer[i + 2] = UInt8((min(1, max(0, b)) * 255).rounded())
        }
      }
    }
    guard let image = PSPixels.image(bytes: output, width: width, height: height) else { throw PSRenderError.image }
    return image
  }

  /// Bilinear, texel centres at (i + 0.5) / size, edges clamped: the way a linear, clamp-to-edge GPU sampler reads it.
  private static func sample(_ layer: Prepared, s: Double, t: Double) -> (r: Double, g: Double, b: Double, a: Double) {
    let fx = s * Double(layer.width) - 0.5, fy = t * Double(layer.height) - 0.5
    let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
    let wx = fx - Double(x0), wy = fy - Double(y0)
    func texel(_ x: Int, _ y: Int) -> (Double, Double, Double, Double) {
      let cx = min(layer.width - 1, max(0, x)), cy = min(layer.height - 1, max(0, y))
      let i = (cy * layer.width + cx) * 4
      return (Double(layer.bytes[i]) / 255, Double(layer.bytes[i + 1]) / 255, Double(layer.bytes[i + 2]) / 255, Double(layer.bytes[i + 3]) / 255)
    }
    let a = texel(x0, y0), b = texel(x0 + 1, y0), c = texel(x0, y0 + 1), d = texel(x0 + 1, y0 + 1)
    func mix(_ p: Double, _ q: Double, _ r: Double, _ s: Double) -> Double {
      (p * (1 - wx) + q * wx) * (1 - wy) + (r * (1 - wx) + s * wx) * wy
    }
    return (mix(a.0, b.0, c.0, d.0), mix(a.1, b.1, c.1, d.1), mix(a.2, b.2, c.2, d.2), mix(a.3, b.3, c.3, d.3))
  }
}

enum PSRendererFactory {
  private static let shared: any PSRendering = {
    if PSMetalProbe.canCompileAndRun(), let metal = try? PSMetalRenderer() { return metal }
    return PSCPURenderer()
  }()

  /// The Metal renderer when the shader compiles and runs here (inside DT Hub too), the CPU one otherwise.
  static func make() -> any PSRendering { shared }
}
