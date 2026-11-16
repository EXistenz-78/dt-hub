import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

@Suite struct LocalEditCompositorTests {
  /// A picture from a per-pixel colour function.
  private func picture(_ w: Int, _ h: Int, _ f: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h {
      for x in 0..<w {
        let (r, g, b) = f(x, y)
        let i = (y * w + x) * 4
        bytes[i] = r
        bytes[i + 1] = g
        bytes[i + 2] = b
      }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
      width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  }

  private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return bytes.prefix(3).map(Int.init)
  }

  private func grey(_ w: Int, _ h: Int, _ v: UInt8) -> CGImage { picture(w, h) { _, _ in (v, v, v) } }

  @Test func theCropHasTheExactPixels() {
    let original = picture(1024, 768) { x, y in (UInt8(x % 256), UInt8(y % 256), UInt8((x + y) % 256)) }
    let crop = LocalEditCompositor.crop(original, to: PixelRect(x: 64, y: 64, width: 512, height: 512))
    #expect(crop?.width == 512 && crop?.height == 512)
    #expect(pixel(crop!, 0, 0) == pixel(original, 64, 64))
    #expect(pixel(crop!, 100, 37) == pixel(original, 164, 101))
  }

  @Test func outsideTheRectNothingChanges() {
    let original = picture(1024, 768) { x, y in (UInt8(x % 256), UInt8(y % 256), 7) }
    let rect = PixelRect(x: 256, y: 128, width: 512, height: 512)
    let out = LocalEditCompositor.montage(
      original: original, retouch: grey(512, 512, 200), rect: rect, matchColors: true)!
    #expect(out.width == 1024 && out.height == 768)
    #expect(pixel(out, 10, 10) == pixel(original, 10, 10))
    #expect(pixel(out, 900, 700) == pixel(original, 900, 700))
  }

  @Test func theCentreIsTheRetouchAndTheEdgeTheOriginal() {
    let original = grey(1024, 768, 100)
    let rect = PixelRect(x: 256, y: 128, width: 512, height: 512)
    let out = LocalEditCompositor.montage(
      original: original, retouch: grey(512, 512, 200), rect: rect, matchColors: false)!
    #expect(pixel(out, 512, 384) == [200, 200, 200])
    #expect(pixel(out, 256, 300) == [100, 100, 100])
    #expect(pixel(out, 500, 128) == [100, 100, 100])
  }

  @Test func aDarkerRetouchIsBroughtToTheOriginalLevel() {
    let rect = PixelRect(x: 256, y: 128, width: 512, height: 512)
    let out = LocalEditCompositor.montage(
      original: grey(1024, 768, 160), retouch: grey(512, 512, 80), rect: rect, matchColors: true)!
    for c in pixel(out, 512, 384) { #expect(abs(c - 160) <= 2) }
  }

  @Test func theGainIsHeldBetweenPoint2And5() {
    let rect = PixelRect(x: 256, y: 128, width: 512, height: 512)
    let out = LocalEditCompositor.montage(
      original: grey(1024, 768, 250), retouch: grey(512, 512, 1), rect: rect, matchColors: true)!
    for c in pixel(out, 512, 384) { #expect(c <= 9) }
  }

  @Test func theRetouchLandsTheRightWayUp() {
    let original = grey(1024, 768, 100)
    let retouch = picture(512, 512) { x, y in (UInt8(x % 256), UInt8(y / 2), 50) }
    let rect = PixelRect(x: 128, y: 0, width: 512, height: 512)
    let out = LocalEditCompositor.montage(
      original: original, retouch: retouch, rect: rect, matchColors: false)!
    #expect(pixel(out, rect.x + 300, rect.y + 60) == pixel(retouch, 300, 60))
    #expect(pixel(out, rect.x + 100, rect.y + 400) == pixel(retouch, 100, 400))
    #expect(pixel(out, rect.x + 300, rect.y + 512) == [100, 100, 100])
  }

  @Test func aRetouchOfAnotherSizeIsRefused() {
    let rect = PixelRect(x: 0, y: 0, width: 512, height: 512)
    #expect(
      LocalEditCompositor.montage(
        original: grey(1024, 768, 100), retouch: grey(511, 512, 100), rect: rect, matchColors: true)
        == nil)
  }

  @Test func aMaskSavedSmallerIsCroppedToTheSameArea() {
    let mask = grey(1024, 768, 255)
    let crop = LocalEditCompositor.crop(
      mask, to: PixelRect(x: 1024, y: 768, width: 1024, height: 768), fullWidth: 4096, fullHeight: 3072)
    #expect(crop?.width == 256 && crop?.height == 192)
  }

  /// Release timing measured at 0.34 s; a debug build needs about 10 s, so it only runs on request.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["DTHUB_SLOW_TESTS"] != nil))
  func aBigPasteIsFast() {
    let original = grey(8192, 5000, 120)
    let retouch = grey(4096, 4096, 90)
    let start = Date()
    let out = LocalEditCompositor.montage(
      original: original, retouch: retouch, rect: PixelRect(x: 1000, y: 400, width: 4096, height: 4096),
      matchColors: true)
    #expect(out != nil)
    // Debug builds are ~30x slower than release (0.3 s there); this only guards against a per-pixel CGContext regression.
    #expect(Date().timeIntervalSince(start) < 40)
  }
}
