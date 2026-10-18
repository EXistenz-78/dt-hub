import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import TiledUpscale

struct TUImageTests {
  /// An RGBA image whose pixel (x, y) is `color(x, y)`.
  private func image(_ width: Int, _ height: Int, _ color: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let (r, g, b) = color(x, y)
        let base = (y * width + x) * 4
        bytes[base] = r
        bytes[base + 1] = g
        bytes[base + 2] = b
      }
    }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false,
      intent: .defaultIntent)!
  }

  /// The RGBA of pixel (x, y), top left origin.
  private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setBlendMode(.copy)
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return data
  }

  private func decode(_ png: Data) -> CGImage? {
    CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
  }

  @Test func scalingAndCroppingGivesTheExpectedSizeAndCut() throws {
    // 10 × 10, the red channel grows with x: ×2 is 20 wide, cut to 16 with 2 off each side.
    let source = image(10, 10) { x, _ in (UInt8(x * 25), 0, 0) }
    let size = ScaledSize(width: 16, height: 16, cropLeft: 2, cropTop: 2)
    let canvas = try #require(TUCanvas(scaling: source, factor: 2, size: size))
    let result = try #require(canvas.image())
    #expect(result.width == 16 && result.height == 16)
    // The first column is scaled column 2 (source ≈ 1.25), the last is scaled column 17 (source ≈ 8.25).
    #expect(abs(Int(pixel(result, 0, 8)[0]) - 31) < 20)
    #expect(abs(Int(pixel(result, 15, 8)[0]) - 206) < 20)
  }

  @Test func cropReturnsTheRect() throws {
    let canvas = try #require(TUCanvas(scaling: image(64, 64) { x, y in x == 10 && y == 20 ? (255, 0, 0) : (0, 0, 255) }, factor: 1,
      size: ScaledSize(width: 64, height: 64, cropLeft: 0, cropTop: 0)))
    let piece = try #require(canvas.crop(TileRect(x: 8, y: 18, width: 4, height: 4)))
    #expect(piece.width == 4 && piece.height == 4)
    #expect(pixel(piece, 2, 2) == [255, 0, 0, 255])
    #expect(pixel(piece, 0, 0) == [0, 0, 255, 255])
  }

  @Test func pasteDoesNotShiftPixels() throws {
    let canvas = try #require(TUCanvas(width: 256, height: 256))
    let tile = image(64, 64) { x, y in x == 10 && y == 20 ? (200, 100, 50) : (7, 7, 7) }
    canvas.paste(tile, at: TileRect(x: 128, y: 192, width: 64, height: 64))
    let result = try #require(canvas.image())
    #expect(pixel(result, 138, 212) == [200, 100, 50, 255])
    #expect(pixel(result, 128, 192) == [7, 7, 7, 255])
    #expect(pixel(result, 127, 192) == [0, 0, 0, 0], "outside the pasted tile nothing changed")
    #expect(pixel(result, 138, 191) == [0, 0, 0, 0])
  }

  @Test func maskPNGHas255InsideAndZeroOutside() throws {
    let data = try #require(TUImage.maskPNG(width: 8, height: 6, masked: TileRect(x: 3, y: 2, width: 5, height: 4)))
    let mask = try #require(decode(data))
    #expect(mask.width == 8 && mask.height == 6)
    #expect(pixel(mask, 3, 2)[0] == 255)
    #expect(pixel(mask, 7, 5)[0] == 255)
    #expect(pixel(mask, 2, 2)[0] == 0)
    #expect(pixel(mask, 3, 1)[0] == 0)
  }

  @Test func maskPNGWithNilIsAllZero() throws {
    let data = try #require(TUImage.maskPNG(width: 4, height: 4, masked: nil))
    let mask = try #require(decode(data))
    #expect(pixel(mask, 1, 1)[0] == 0)
  }

  @Test func pngRoundTrip() throws {
    let original = image(8, 8) { x, y in (UInt8(x * 30), UInt8(y * 30), 9) }
    let data = try #require(TUImage.pngData(original))
    let back = try #require(decode(data))
    #expect(pixel(back, 5, 3) == pixel(original, 5, 3))
  }

  @Test func previewScaleAndSizeKeepTheRatio() {
    #expect(TUPreview.scale(width: 2400, height: 1200, maxSide: 1200) == 0.5)
    #expect(TUPreview.scale(width: 800, height: 600, maxSide: 1200) == 1, "a small picture is not enlarged")
    let size = TUPreview.size(width: 1280, height: 1024, maxSide: 1200)
    #expect(size.width == 1200 && size.height == 960)
  }

  @Test func previewTileRectsMeetWithNoGap() {
    // Two tiles that touch at x = 768: at any scale the first ends where the second starts.
    for scale in [0.3, 0.5, 0.9375] {
      let first = TUPreview.rect(of: TileRect(x: 0, y: 0, width: 768, height: 100), scale: scale)
      let second = TUPreview.rect(of: TileRect(x: 768, y: 0, width: 512, height: 100), scale: scale)
      #expect(first.maxX == second.minX)
    }
  }

  @Test func previewBaseHasTheRatioOfTheFinalPictureAndTheCutApplied() throws {
    // 100 × 50 at ×2 is 200 × 100; cut by 4 on the left and right it is 192 × 100; shown at most 96 px on a side.
    let source = image(100, 50) { x, _ in (UInt8(x * 2), 0, 0) }
    let size = ScaledSize(width: 192, height: 100, cropLeft: 4, cropTop: 0)
    let base = try #require(TUPreview.base(of: source, factor: 2, size: size, maxSide: 96))
    #expect(base.width == 96 && base.height == 50)
    // The first column is enlarged column 4 (source ≈ 2) → red ≈ 4; the last is column 195 (source ≈ 97.5) → red ≈ 195.
    #expect(Int(pixel(base, 0, 25)[0]) < 20)
    #expect(Int(pixel(base, 95, 25)[0]) > 170)
  }
}
