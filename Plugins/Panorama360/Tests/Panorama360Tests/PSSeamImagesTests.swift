import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Panorama360

@Suite("Seam pictures")
struct PSSeamImagesTests {
  func columns(_ w: Int, _ h: Int) -> CGImage { TestImages.make(w, h) { x, y in (UInt8(x % 256), UInt8(x / 256), UInt8(y % 256), 255) } }

  @Test func rollingMovesColumnsExactly() throws {
    let image = columns(300, 20)
    let rolled = try #require(PSSeamImages.rolled(image, by: 150))
    #expect(rolled.width == 300 && rolled.height == 20)
    for (x, y) in [(0, 0), (149, 5), (150, 7), (299, 19)] {
      let a = TestImages.pixel(rolled, x, y), b = TestImages.pixel(image, (x + 150) % 300, y)
      #expect(a.r == b.r && a.g == b.g && a.b == b.b, "x \(x)")
    }
  }

  @Test func rollingTwiceByHalfIsTheIdentityEvenForAnOddWidth() throws {
    for w in [300, 301] {
      let image = columns(w, 8)
      let k = w / 2
      let there = try #require(PSSeamImages.rolled(image, by: k))
      let back = try #require(PSSeamImages.rolled(there, by: w - k))
      #expect(PSPixels.rgba(of: back).bytes == PSPixels.rgba(of: image).bytes, "width \(w)")
    }
  }

  @Test func cropTakesTheColumnsAskedForAtFullHeight() throws {
    let image = columns(300, 20)
    let crop = try #require(PSSeamImages.crop(image, x: 100, width: 50))
    #expect(crop.width == 50 && crop.height == 20)
    #expect(TestImages.pixel(crop, 0, 3).r == TestImages.pixel(image, 100, 3).r)
    #expect(TestImages.pixel(crop, 49, 3).r == TestImages.pixel(image, 149, 3).r)
    #expect(PSSeamImages.crop(image, x: 280, width: 50) == nil, "outside the picture")
  }

  @Test func theMaskIsGreyWith255OnlyInTheBand() throws {
    let data = try #require(PSSeamImages.maskPNG(square: 256, bandWidth: 128))
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 256 && image.height == 256 && image.bitsPerPixel == 8)
    let bytes = PSPixels.rgba(of: image).bytes
    func value(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * 256 + x) * 4] }
    for y in [0, 128, 255] {
      #expect(value(63, y) == 0 && value(64, y) == 255 && value(191, y) == 255 && value(192, y) == 0)
    }
  }

  // MARK: Fusion

  func plan() throws -> PSSeamPlan {
    guard case .success(let plan) = PSSeam.plan(width: 512, height: 256) else { throw PSSeamReason.notTwoToOne }
    return plan
  }

  @Test func composeKeepsTheOriginalOutsideTheBandAndTheGeneratedInsideIt() throws {
    let plan = try plan()
    let red = TestImages.solid(512, 256, 255, 0, 0)
    let blue = TestImages.solid(256, 256, 0, 0, 255)
    let out = try #require(PSSeamImages.compose(rolled: red, generated: blue, plan: plan))
    #expect(out.width == 512 && out.height == 256)
    let centre = TestImages.pixel(out, plan.seamX, 128)
    #expect(centre.b > 200 && centre.r < 30, "\(centre)")
    let context = TestImages.pixel(out, plan.bandX - 20, 128)
    #expect(context.r == 255 && context.b == 0, "\(context)")
    let far = TestImages.pixel(out, 5, 10)
    #expect(far.r == 255 && far.b == 0)
  }

  @Test func theFadeIsMonotonicOnBothEdgesOfTheBand() throws {
    let plan = try plan()
    let out = try #require(PSSeamImages.compose(rolled: TestImages.solid(512, 256, 255, 0, 0), generated: TestImages.solid(256, 256, 0, 0, 255), plan: plan))
    var lastRed = 256
    for x in (plan.bandX - 2)...(plan.bandX + plan.fade + 2) {
      let r = TestImages.pixel(out, x, 100).r
      #expect(r <= lastRed, "left edge x \(x)")
      lastRed = r
    }
    #expect(TestImages.pixel(out, plan.bandX, 100).r > 200 && TestImages.pixel(out, plan.bandX + plan.fade, 100).r < 40)
    var lastRight = -1
    for x in (plan.bandX + plan.bandWidth - plan.fade - 2)...(plan.bandX + plan.bandWidth + 1) {
      let r = TestImages.pixel(out, x, 100).r
      #expect(r >= lastRight, "right edge x \(x)")
      lastRight = r
    }
  }

  @Test func theToneIsBroughtTowardsTheOriginal() throws {
    let plan = try plan()
    let grey = TestImages.solid(512, 256, 128, 128, 128)
    let bright = TestImages.solid(256, 256, 230, 230, 230)
    let out = try #require(PSSeamImages.compose(rolled: grey, generated: bright, plan: plan))
    let centre = TestImages.pixel(out, plan.seamX, 128)
    #expect(abs(centre.r - 128) < 12 && abs(centre.g - 128) < 12, "\(centre)")
  }

  @Test func composeRejectsAGeneratedPictureOfAnotherSizeAndAPanoramaThatIsNotThePlans() throws {
    let plan = try plan()
    #expect(PSSeamImages.compose(rolled: TestImages.solid(512, 256, 1, 1, 1), generated: TestImages.solid(128, 128, 1, 1, 1), plan: plan) == nil)
    #expect(PSSeamImages.compose(rolled: TestImages.solid(500, 256, 1, 1, 1), generated: TestImages.solid(256, 256, 1, 1, 1), plan: plan) == nil)
  }
}
