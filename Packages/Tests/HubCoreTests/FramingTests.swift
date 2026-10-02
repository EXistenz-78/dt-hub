import CoreGraphics
import HubKit
import Testing

@testable import HubCore

struct FramingMathTests {
  func crop(_ iw: Int, _ ih: Int, canvas cw: Int, _ ch: Int, x: Double = 0, y: Double = 0) -> CGRect {
    FramingMath.cropRect(
      imageWidth: iw, imageHeight: ih, canvasWidth: cw, canvasHeight: ch, framing: Framing(offsetX: x, offsetY: y))
  }

  @Test func aSquareImageInA43CanvasLosesAQuarterAboveAndBelow() {
    let rect = crop(1000, 1000, canvas: 1200, 900)
    #expect(rect == CGRect(x: 0, y: 125, width: 1000, height: 750))
    let loss = FramingMath.loss(imageWidth: 1000, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900)
    #expect(loss.axis == .vertical)
    #expect(abs(loss.fraction - 0.25) < 0.0001)
  }

  @Test func theOffsetMovesTheCutAlongTheCroppedAxisOnly() {
    #expect(crop(1000, 1000, canvas: 1200, 900, x: 1, y: -1) == CGRect(x: 0, y: 0, width: 1000, height: 750))
    #expect(crop(1000, 1000, canvas: 1200, 900, x: -1, y: 1) == CGRect(x: 0, y: 250, width: 1000, height: 750))
  }

  @Test func aTallImageInA43CanvasLosesMoreThanAThird() {
    let rect = crop(750, 1000, canvas: 1200, 900)
    #expect(rect.width == 750)
    #expect(abs(rect.height - 562.5) < 0.0001)
    let loss = FramingMath.loss(imageWidth: 750, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900)
    #expect(loss.axis == .vertical)
    #expect(abs(loss.fraction - 0.4375) < 0.0001)
  }

  @Test func aWideImageInASquareCanvasLosesSidewaysAndTheOffsetFollows() {
    #expect(crop(2000, 1000, canvas: 512, 512) == CGRect(x: 500, y: 0, width: 1000, height: 1000))
    #expect(crop(2000, 1000, canvas: 512, 512, x: -1) == CGRect(x: 0, y: 0, width: 1000, height: 1000))
    #expect(FramingMath.loss(imageWidth: 2000, imageHeight: 1000, canvasWidth: 512, canvasHeight: 512).axis == .horizontal)
  }

  @Test func theSameRatioLosesNothing() {
    #expect(crop(1600, 1200, canvas: 1024, 768) == CGRect(x: 0, y: 0, width: 1600, height: 1200))
    let loss = FramingMath.loss(imageWidth: 1600, imageHeight: 1200, canvasWidth: 1024, canvasHeight: 768)
    #expect(loss.axis == nil)
    #expect(loss.fraction == 0)
  }

  @Test func adaptingKeepsTheAreaAndSnapsTo64() {
    // 1344×1024 = 1 376 256 px²; a square of that area is 1173 px, snapped to 1152.
    #expect(FramingMath.adaptedSize(imageWidth: 800, imageHeight: 800, currentWidth: 1344, currentHeight: 1024) == Size(width: 1152, height: 1152))
    // 3:4 portrait: 1016×1355 → 1024×1344.
    #expect(FramingMath.adaptedSize(imageWidth: 768, imageHeight: 1024, currentWidth: 1344, currentHeight: 1024) == Size(width: 1024, height: 1344))
  }

  @Test func adaptingStaysInsideTheLimits() {
    let wide = FramingMath.adaptedSize(imageWidth: 10_000, imageHeight: 100, currentWidth: 1024, currentHeight: 1024)
    #expect(wide.width <= 2048 && wide.height >= 64)
    let high = FramingMath.adaptedSize(imageWidth: 100, imageHeight: 10_000, currentWidth: 1024, currentHeight: 1024)
    #expect(high.height <= 2048 && high.width >= 64)
    let limited = FramingMath.adaptedSize(imageWidth: 100, imageHeight: 100, currentWidth: 2048, currentHeight: 2048, limit: 1024)
    #expect(limited == Size(width: 1024, height: 1024))
  }
}

struct InputComposerTests {
  /// An image whose left half is red and right half is blue.
  func twoTone(width: Int = 200, height: Int = 100) -> CGImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    return context.makeImage()!
  }

  /// Red and blue of the pixel at (x, y), counted from the top-left.
  func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, b: Int) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(bytes[0]), Int(bytes[2]))
  }

  @Test func theFramedImageHasTheExactCanvasSize() throws {
    let framed = try #require(InputComposer.frame(twoTone(), toWidth: 128, height: 64, framing: Framing()))
    #expect(framed.width == 128)
    #expect(framed.height == 64)
  }

  @Test func aSquareCanvasShowsTheLeftOrTheRightHalfAccordingToTheOffset() throws {
    let left = try #require(InputComposer.frame(twoTone(), toWidth: 64, height: 64, framing: Framing(offsetX: -1)))
    #expect(pixel(left, 5, 32).r > 250 && pixel(left, 58, 32).r > 250)
    let right = try #require(InputComposer.frame(twoTone(), toWidth: 64, height: 64, framing: Framing(offsetX: 1)))
    #expect(pixel(right, 5, 32).b > 250 && pixel(right, 58, 32).b > 250)
    let centered = try #require(InputComposer.frame(twoTone(), toWidth: 64, height: 64, framing: Framing()))
    #expect(pixel(centered, 5, 32).r > 250)
    #expect(pixel(centered, 58, 32).b > 250)
  }

  @Test func theFramedImageIsOpaque() throws {
    let framed = try #require(InputComposer.frame(twoTone(), toWidth: 64, height: 64, framing: Framing()))
    #expect(framed.alphaInfo == .noneSkipLast || framed.alphaInfo == .premultipliedLast)
  }
}
