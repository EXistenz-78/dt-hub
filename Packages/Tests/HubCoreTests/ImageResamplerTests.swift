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

struct ImageResamplerReviewTests {
  /// A flat colour in Display P3.
  static func p3Flat(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, size: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(colorSpace: space, components: [r, g, b, 1])!)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()!
  }

  @Test func wideGamutKeepsItsColourWithCoreImage() throws {
    let source = Self.p3Flat(200 / 255, 100 / 255, 50 / 255, size: 16)
    let reference = ImageResamplerTests.pixels(try #require(ImageResampler.scaled(source, toWidth: 32, height: 32, with: .coreGraphics)))
    let soft = ImageResamplerTests.pixels(try #require(ImageResampler.scaled(source, toWidth: 32, height: 32, with: .catmullRom)))
    let i = (16 * 32 + 16) * 4
    for c in 0..<3 { #expect(abs(Int(reference[i + c]) - Int(soft[i + c])) <= 2, "channel \(c): \(reference[i + c]) vs \(soft[i + c])") }
  }

  @Test func oneToOneIsNotResampled() throws {
    let source = ImageResamplerTests.noise(size: 64)
    let framed = try #require(
      InputComposer.frame(source, toWidth: 64, height: 64, framing: Framing(), resampling: .bSpline))
    #expect(ImageResamplerTests.pixels(framed) == ImageResamplerTests.pixels(source))
  }

  @Test func highZoomScalesOnlyWhatTheCanvasShows() {
    // 64 px at zoom +100 in a 256 canvas: the whole image would be 1024 px; the canvas sees 256 of them.
    let region = InputComposer.visibleRegion(
      drawn: CGRect(x: -384, y: -384, width: 1024, height: 1024), canvasWidth: 256, canvasHeight: 256, rotation: 0)
    #expect(region == CGRect(x: 384, y: 384, width: 256, height: 256))
  }

  @Test func highZoomMatchesTheWholeScale() throws {
    let source = ImageResamplerTests.noise(size: 64)
    let framing = Framing(zoom: 100, offsetX: 0.3, offsetY: -0.2)
    let framed = try #require(InputComposer.frame(source, toWidth: 256, height: 256, framing: framing, resampling: .catmullRom))
    // The same picture from the whole image scaled, then cut where the canvas looks.
    let crop = FramingMath.cropRect(imageWidth: 64, imageHeight: 64, canvasWidth: 256, canvasHeight: 256, framing: framing)
    let scale = 256 / crop.width
    let whole = try #require(ImageResampler.scaled(source, toWidth: Int((64 * scale).rounded()), height: Int((64 * scale).rounded()), with: .catmullRom))
    let cut = try #require(whole.cropping(to: CGRect(x: (crop.minX * scale).rounded(), y: (crop.minY * scale).rounded(), width: 256, height: 256)))
    let a = ImageResamplerTests.pixels(framed)
    let b = ImageResamplerTests.pixels(cut)
    let differences = zip(a, b).enumerated().filter { $0.offset % 4 != 3 }.map { abs(Int($0.element.0) - Int($0.element.1)) }
    let mean = Double(differences.reduce(0, +)) / Double(differences.count)
    // The reference is itself a Core Image render, of the whole 1024 px picture, which Core Image makes in tiles: a few
    // pixels along its seams differ by some levels (measured mean 0.16 of 255). A wrong place would be ~20 on noise.
    #expect(mean < 0.5, "mean difference \(mean), largest \(differences.max() ?? 0)")
  }

  /// A 4× reduction of noise compared with the exact mean of each 4×4 block: a method that skipped pixels (aliasing) would
  /// be far from it; the filters differ only by their shape (measured: bilinear 0.3, Catmull-Rom 7, B-spline 11.5).
  @Test(arguments: [Resampling.bilinear, .catmullRom, .mitchell, .bSpline, .lanczos])
  func reductionFollowsTheBlockMean(_ method: Resampling) throws {
    let source = ImageResamplerTests.noise(size: 64)
    let l = ImageResamplerTests.luminance(source)
    let reduced = ImageResamplerTests.luminance(try #require(ImageResampler.scaled(source, toWidth: 16, height: 16, with: method)))
    var total = 0.0
    for y in 0..<16 {
      for x in 0..<16 {
        var block = 0.0
        for dy in 0..<4 { for dx in 0..<4 { block += l[(y * 4 + dy) * 64 + x * 4 + dx] } }
        total += abs(reduced[y * 16 + x] - block / 16)
      }
    }
    #expect(total / 256 < 14, "mean distance from the block mean \(total / 256)")
  }
}
