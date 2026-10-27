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

  @Test func theGreenFillsTheColumnsAskedForAtFullHeightAndNothingElse() throws {
    let image = columns(300, 20)
    let painted = try #require(PSSeamImages.paintGreen(image, x: 100, width: 50))
    #expect(painted.width == 300 && painted.height == 20)
    for y in [0, 9, 19] {
      for x in [100, 125, 149] {
        let p = TestImages.pixel(painted, x, y)
        #expect(p.r == 0 && p.g == 255 && p.b == 0 && p.a == 255, "x \(x) y \(y): \(p)")
      }
      for x in [0, 99, 150, 299] {
        #expect(TestImages.pixel(painted, x, y).r == TestImages.pixel(image, x, y).r, "x \(x) is not touched")
      }
    }
    #expect(PSSeamImages.paintGreen(image, x: 280, width: 50) == nil, "outside the picture")
  }

  // MARK: Fusion

  func plan() throws -> PSSeamPlan {
    guard case .success(let plan) = PSSeam.plan(width: 512, height: 256) else { throw PSSeamReason.notTwoToOne }
    return plan
  }

  @Test func composeKeepsTheOriginalOutsideTheBandAndTheGeneratedInsideIt() throws {
    let plan = try plan()
    let red = TestImages.solid(512, 256, 255, 0, 0)
    let blue = TestImages.solid(512, 256, 0, 0, 255)
    let out = try #require(PSSeamImages.compose(rolled: red, generated: blue, plan: plan))
    #expect(out.width == 512 && out.height == 256)
    let centre = TestImages.pixel(out, plan.seamX, 128)
    #expect(centre.b > 200 && centre.r < 30, "\(centre)")
    let context = TestImages.pixel(out, plan.bandX - 20, 128)
    #expect(context.r == 255 && context.b == 0, "\(context)")
    let far = TestImages.pixel(out, 5, 10)
    #expect(far.r == 255 && far.b == 0)
  }

  @Test func onlyTheBandOfTheGeneratedPictureIsUsed() throws {
    let plan = try plan()
    let grey = TestImages.solid(512, 256, 100, 100, 100)
    // The model made the whole panorama; outside the band its picture is red, inside it is blue.
    let generated = TestImages.make(512, 256) { x, _ in
      (plan.bandX..<(plan.bandX + plan.bandWidth)).contains(x) ? (100, 100, 255, 255) : (255, 0, 0, 255)
    }
    let out = try #require(PSSeamImages.compose(rolled: grey, generated: generated, plan: plan))
    for x in [0, 50, plan.bandX - 3, plan.bandX + plan.bandWidth + 3, 500] {
      let p = TestImages.pixel(out, x, 100)
      #expect(p.r == 100 && p.g == 100 && p.b == 100, "x \(x) keeps the original: \(p)")
    }
    #expect(TestImages.pixel(out, plan.seamX, 100).b > 150, "the middle of the band comes from the generated picture")
  }

  @Test func theFadeIsMonotonicOnBothEdgesOfTheBand() throws {
    let plan = try plan()
    let out = try #require(PSSeamImages.compose(rolled: TestImages.solid(512, 256, 255, 0, 0), generated: TestImages.solid(512, 256, 0, 0, 255), plan: plan))
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
    let bright = TestImages.solid(512, 256, 230, 230, 230)
    let out = try #require(PSSeamImages.compose(rolled: grey, generated: bright, plan: plan))
    let centre = TestImages.pixel(out, plan.seamX, 128)
    #expect(abs(centre.r - 128) < 12 && abs(centre.g - 128) < 12, "\(centre)")
  }

  @Test func composeRejectsAGeneratedPictureOfAnotherSizeAndAPanoramaThatIsNotThePlans() throws {
    let plan = try plan()
    #expect(PSSeamImages.compose(rolled: TestImages.solid(512, 256, 1, 1, 1), generated: TestImages.solid(128, 128, 1, 1, 1), plan: plan) == nil)
    #expect(PSSeamImages.compose(rolled: TestImages.solid(500, 256, 1, 1, 1), generated: TestImages.solid(512, 256, 1, 1, 1), plan: plan) == nil)
  }

  /// A panorama (rolled) whose left half is darker than its right half: the exposure steps exactly at the seam, as when the two edges of a
  /// generated panorama were made at different levels.
  func steppedPanorama(dark: UInt8, bright: UInt8) -> CGImage {
    TestImages.make(512, 256) { x, _ in x < 256 ? (dark, dark, dark, 255) : (bright, bright, bright, 255) }
  }

  @Test func aBrightnessStepBetweenTheTwoSidesDoesNotComeBackAtTheSeam() throws {
    let plan = try plan()
    let out = try #require(PSSeamImages.compose(rolled: steppedPanorama(dark: 100, bright: 160), generated: TestImages.solid(512, 256, 130, 130, 130), plan: plan))
    let left = TestImages.pixel(out, plan.seamX - 1, 128).r, right = TestImages.pixel(out, plan.seamX, 128).r
    #expect(abs(left - right) <= 3, "no step at the seam: \(left) \(right)")
    #expect(abs(TestImages.pixel(out, plan.bandX, 128).r - 100) <= 4, "the left edge of the band meets the left side")
    #expect(abs(TestImages.pixel(out, plan.bandX + plan.bandWidth - 1, 128).r - 160) <= 4, "the right edge meets the right side")
    // And it goes from one level to the other without overshooting.
    var last = 0
    for x in stride(from: plan.bandX, to: plan.bandX + plan.bandWidth, by: 4) {
      let v = TestImages.pixel(out, x, 128).r
      #expect(v >= last - 1 && v <= 165, "x \(x): \(v)")
      last = v
    }
  }

  @Test func evenSidesAndAnEvenGeneratedPictureStayEven() throws {
    let plan = try plan()
    let out = try #require(PSSeamImages.compose(rolled: TestImages.solid(512, 256, 120, 120, 120), generated: TestImages.solid(512, 256, 120, 120, 120), plan: plan))
    for x in stride(from: 0, to: 512, by: 32) { #expect(abs(TestImages.pixel(out, x, 100).r - 120) <= 1, "x \(x)") }
  }
}
