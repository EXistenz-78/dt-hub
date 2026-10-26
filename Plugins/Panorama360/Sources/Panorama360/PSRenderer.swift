import CoreGraphics
import Foundation

/// One picture to put on the panorama, in its place: the frame it looks along and how opaque it is.
struct PSLayer: @unchecked Sendable {
  var image: CGImage
  var basis: StickerBasis
  var opacity: Double
  /// Softens the edge of the picture over this fraction of its side (0 = a hard edge): the patch of a retouch put back into a panorama.
  var feather = 0.0
}

/// What a view from the camera looks at: the stickers over green, or a whole panorama (an ERP picture).
enum PSViewSource: @unchecked Sendable {
  case layers([PSLayer])
  case panorama(CGImage)
}

enum PSRenderError: Error, Equatable {
  case metal(String)
  case image
}

/// Draws the panorama: the layers in order (the first is the bottom one) over `#00ff00`, or over `background` (an ERP picture), as a
/// `width × height` equirectangular picture. `uOffset` rolls the picture sideways, in turns. `renderView` draws what a camera in the centre of
/// the sphere sees.
protocol PSRendering: Sendable {
  /// «Metal» or «CPU»: which one draws.
  var backendName: String { get }
  func render(_ layers: [PSLayer], width: Int, height: Int, uOffset: Double, background: CGImage?) throws -> CGImage
  func renderView(_ source: PSViewSource, camera: PSCamera, width: Int, height: Int) throws -> CGImage
}

extension PSRendering {
  func render(_ layers: [PSLayer], width: Int, height: Int, uOffset: Double) throws -> CGImage {
    try render(layers, width: width, height: height, uOffset: uOffset, background: nil)
  }
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
  var backendName: String { "CPU" }

  private struct Prepared: Sendable {
    var bytes: [UInt8]
    var width: Int
    var height: Int
    var basis: StickerBasis
    var opacity: Double
    var feather: Double
  }

  private struct Picture: Sendable {
    var bytes: [UInt8]
    var width: Int
    var height: Int
  }

  private static func prepare(_ layers: [PSLayer]) -> [Prepared] {
    layers.map { layer in
      let pixels = PSPixels.rgba(of: layer.image)
      return Prepared(
        bytes: pixels.bytes, width: pixels.width, height: pixels.height, basis: layer.basis, opacity: layer.opacity,
        feather: layer.feather)
    }
  }

  func render(_ layers: [PSLayer], width: Int, height: Int, uOffset: Double, background: CGImage?) throws -> CGImage {
    let prepared = Self.prepare(layers)
    let backdrop = background.map { image -> Picture in
      let pixels = PSPixels.rgba(of: image)
      return Picture(bytes: pixels.bytes, width: pixels.width, height: pixels.height)
    }
    let sinLon = (0..<width).map { sin((((Double($0) + 0.5) / Double(width)) + uOffset - 0.5) * 2 * .pi) }
    let cosLon = (0..<width).map { cos((((Double($0) + 0.5) / Double(width)) + uOffset - 0.5) * 2 * .pi) }
    return try Self.draw(width: width, height: height) { x, y in
      let lat = (0.5 - (Double(y) + 0.5) / Double(height)) * .pi
      let d = Vec3(x: sinLon[x] * cos(lat), y: sin(lat), z: cosLon[x] * cos(lat))
      var color = backdrop.map { Self.panorama($0, d) } ?? (0, 1, 0)
      Self.composite(prepared, d, &color)
      return color
    }
  }

  func renderView(_ source: PSViewSource, camera: PSCamera, width: Int, height: Int) throws -> CGImage {
    switch source {
    case .layers(let layers):
      let prepared = Self.prepare(layers)
      return try Self.draw(width: width, height: height) { x, y in
        let d = camera.ray(x: Double(x) + 0.5, y: Double(y) + 0.5, width: Double(width), height: Double(height))
        var color = (0.0, 1.0, 0.0)
        Self.composite(prepared, d, &color)
        return color
      }
    case .panorama(let image):
      let pixels = PSPixels.rgba(of: image)
      let picture = Picture(bytes: pixels.bytes, width: pixels.width, height: pixels.height)
      return try Self.draw(width: width, height: height) { x, y in
        Self.panorama(picture, camera.ray(x: Double(x) + 0.5, y: Double(y) + 0.5, width: Double(width), height: Double(height)))
      }
    }
  }

  /// Fills a picture row by row on all cores with the colour `pixel` gives for each (x, y).
  private static func draw(width: Int, height: Int, pixel: @escaping @Sendable (Int, Int) -> (Double, Double, Double)) throws -> CGImage {
    var output = [UInt8](repeating: 255, count: width * height * 4)
    output.withUnsafeMutableBufferPointer { buffer in
      let box = Box(pointer: buffer.baseAddress!)
      DispatchQueue.concurrentPerform(iterations: height) { y in
        for x in 0..<width {
          let (r, g, b) = pixel(x, y)
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

  /// The layers in order over `color`, each as premultiplied alpha, with the feather at its edge.
  private static func composite(_ layers: [Prepared], _ d: Vec3, _ color: inout (Double, Double, Double)) {
    for layer in layers {
      let dz = d.dot(layer.basis.forward)
      guard dz > 1e-5 else { continue }
      let s = d.dot(layer.basis.right) / dz / layer.basis.tanX * 0.5 + 0.5
      let t = 0.5 - d.dot(layer.basis.up) / dz / layer.basis.tanY * 0.5
      guard s >= 0, s <= 1, t >= 0, t <= 1 else { continue }
      var strength = layer.opacity
      if layer.feather > 0 {
        let k = min(1, max(0, min(min(s, 1 - s), min(t, 1 - t)) / layer.feather))
        strength *= k * k * (3 - 2 * k)
      }
      let c = sample(layer.bytes, layer.width, layer.height, s: s, t: t, wrapsSideways: false)
      let keep = 1 - c.a * strength
      color = (c.r * strength + color.0 * keep, c.g * strength + color.1 * keep, c.b * strength + color.2 * keep)
    }
  }

  /// The colour a panorama has in a direction: longitude wraps, latitude is held at the edges.
  private static func panorama(_ picture: Picture, _ d: Vec3) -> (Double, Double, Double) {
    let p = PSProjection.point(of: d)
    let c = sample(picture.bytes, picture.width, picture.height, s: p.u, t: p.v, wrapsSideways: true)
    return (c.r, c.g, c.b)
  }

  /// Bilinear, texel centres at (i + 0.5) / size, edges clamped (or wrapped sideways): the way a linear GPU sampler reads it.
  private static func sample(_ bytes: [UInt8], _ width: Int, _ height: Int, s: Double, t: Double, wrapsSideways: Bool)
    -> (r: Double, g: Double, b: Double, a: Double)
  {
    let fx = s * Double(width) - 0.5, fy = t * Double(height) - 0.5
    let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
    let wx = fx - Double(x0), wy = fy - Double(y0)
    func texel(_ x: Int, _ y: Int) -> (Double, Double, Double, Double) {
      let cx = wrapsSideways ? ((x % width) + width) % width : min(width - 1, max(0, x))
      let cy = min(height - 1, max(0, y))
      let i = (cy * width + cx) * 4
      return (Double(bytes[i]) / 255, Double(bytes[i + 1]) / 255, Double(bytes[i + 2]) / 255, Double(bytes[i + 3]) / 255)
    }
    let a = texel(x0, y0), b = texel(x0 + 1, y0), c = texel(x0, y0 + 1), d = texel(x0 + 1, y0 + 1)
    func mix(_ p: Double, _ q: Double, _ r: Double, _ s: Double) -> Double {
      (p * (1 - wx) + q * wx) * (1 - wy) + (r * (1 - wx) + s * wx) * wy
    }
    return (mix(a.0, b.0, c.0, d.0), mix(a.1, b.1, c.1, d.1), mix(a.2, b.2, c.2, d.2), mix(a.3, b.3, c.3, d.3))
  }
}

enum PSRendererFactory {
  /// The renderer, and why it is the CPU one when it is.
  private static let choice: (renderer: any PSRendering, fallbackReason: String?) = {
    guard PSMetalProbe.canCompileAndRun() else { return (PSCPURenderer(), "the Metal test shader did not compile or run here") }
    do { return (try PSMetalRenderer(), nil) } catch { return (PSCPURenderer(), "\(error)") }
  }()

  /// The Metal renderer when the shader compiles and runs here (inside DT Hub too), the CPU one otherwise.
  static func make() -> any PSRendering { choice.renderer }

  /// Why Metal is not in use; nil when it is.
  static var fallbackReason: String? { choice.fallbackReason }
}
