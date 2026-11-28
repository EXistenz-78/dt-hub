import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

struct ImageResamplerTests {
  /// An RGBA8 image from its pixels, row by row from the top.
  static func image(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let (r, g, b) = pixel(x, y)
        let i = (y * width + x) * 4
        (bytes[i], bytes[i + 1], bytes[i + 2]) = (r, g, b)
      }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  }

  /// The pixels of an image as RGBA8, row by row from the top.
  static func pixels(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(
      data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return bytes
  }

  static func luminance(_ image: CGImage) -> [Double] {
    let p = pixels(image)
    return (0..<(image.width * image.height)).map { (Double(p[$0 * 4]) + Double(p[$0 * 4 + 1]) + Double(p[$0 * 4 + 2])) / 3 }
  }

  /// Mean absolute Laplacian of the luminance, inside the border.
  static func laplacian(_ image: CGImage) -> Double {
    let l = luminance(image)
    let w = image.width
    var sum = 0.0
    var count = 0
    for y in 1..<(image.height - 1) {
      for x in 1..<(w - 1) {
        let c = l[y * w + x]
        sum += abs(4 * c - l[y * w + x - 1] - l[y * w + x + 1] - l[(y - 1) * w + x] - l[(y + 1) * w + x])
        count += 1
      }
    }
    return sum / Double(count)
  }

  /// Deterministic noise: the same picture on every run.
  static func noise(size: Int) -> CGImage {
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    var values = [UInt8]()
    for _ in 0..<(size * size) {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      values.append(UInt8(truncatingIfNeeded: state >> 56))
    }
    return image(width: size, height: size) { x, y in
      let v = values[y * size + x]
      return (v, v, v)
    }
  }

  @Test func nearestDuplicatesPixels() throws {
    let colors: [(UInt8, UInt8, UInt8)] = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0)]
    let source = Self.image(width: 2, height: 2) { x, y in colors[y * 2 + x] }
    let scaled = try #require(ImageResampler.scaled(source, toWidth: 4, height: 4, with: .nearest))
    let p = Self.pixels(scaled)
    for y in 0..<4 {
      for x in 0..<4 {
        let expected = colors[(y / 2) * 2 + x / 2]
        let i = (y * 4 + x) * 4
        #expect(p[i] == expected.0 && p[i + 1] == expected.1 && p[i + 2] == expected.2, "pixel \(x),\(y) = \(p[i]),\(p[i+1]),\(p[i+2])")
      }
    }
  }

  @Test func smoothnessOrder() throws {
    let source = Self.noise(size: 32)
    func energy(_ method: Resampling) throws -> Double {
      Self.laplacian(try #require(ImageResampler.scaled(source, toWidth: 64, height: 64, with: method)))
    }
    let bSpline = try energy(.bSpline)
    let mitchell = try energy(.mitchell)
    let catmullRom = try energy(.catmullRom)
    #expect(bSpline < mitchell)
    #expect(mitchell < catmullRom)
  }

  @Test(arguments: Resampling.allCases)
  func constantStaysConstant(_ method: Resampling) throws {
    let source = Self.image(width: 16, height: 16) { _, _ in (120, 80, 40) }
    let scaled = try #require(ImageResampler.scaled(source, toWidth: 32, height: 32, with: method))
    #expect(scaled.width == 32 && scaled.height == 32)
    let p = Self.pixels(scaled)
    for i in stride(from: 0, to: p.count, by: 4) {
      #expect(abs(Int(p[i]) - 120) <= 1 && abs(Int(p[i + 1]) - 80) <= 1 && abs(Int(p[i + 2]) - 40) <= 1)
      if abs(Int(p[i]) - 120) > 1 { break }
    }
  }

  @Test(arguments: [Resampling.catmullRom, .lanczos])
  func reductionIsSmooth(_ method: Resampling) throws {
    let checker = Self.image(width: 64, height: 64) { x, y in (x + y) % 2 == 0 ? (255, 255, 255) : (0, 0, 0) }
    let reduced = try #require(ImageResampler.scaled(checker, toWidth: 16, height: 16, with: method))
    let l = Self.luminance(reduced)
    let mean = l.reduce(0, +) / Double(l.count)
    let deviation = (l.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(l.count)).squareRoot()
    #expect(deviation < 20, "a 1-pixel checker reduced 4× should be an even grey, got σ \(deviation)")
  }
}
