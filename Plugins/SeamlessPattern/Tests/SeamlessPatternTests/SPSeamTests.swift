import CoreGraphics
import Foundation
import Testing

@testable import SeamlessPattern

@Suite("SPSeam")
struct SPSeamTests {
  /// A sine with a whole number of periods across the picture: the wrap line joins like any other line.
  @Test func aPeriodicPictureHasNoSeam() {
    let image = TestImages.make(128, 128) { x, y, c in
      let v = 128 + 100 * sin(2 * .pi * 4 * Double(x) / 128) * cos(2 * .pi * 3 * Double(y) / 128) + Double(c * 10)
      return Int(v.rounded())
    }
    let r = SPSeam.check(image)
    #expect(r.leftRight.status == .pass)
    #expect(r.upDown.status == .pass)
  }

  @Test func aHorizontalRampFailsLeftRight() {
    let image = TestImages.make(128, 96) { x, _, _ in (x * 255) / 127 }
    #expect(SPSeam.check(image).leftRight.status == .fail)
  }

  @Test func aSmallPictureIsNotApplicable() {
    let image = TestImages.make(48, 48) { x, y, _ in x * 5 + y }
    let r = SPSeam.check(image)
    #expect(r.leftRight.status == .notApplicable)
    #expect(r.upDown.status == .notApplicable)
    #expect(r.leftRight.ratio == nil)
  }

  @Test func aFlatPictureIsATiePass() {
    let image = TestImages.make(128, 128) { _, _, _ in 90 }
    let r = SPSeam.check(image)
    #expect(r.leftRight.status == .pass)
    #expect(r.upDown.status == .pass)
  }

  // Reference values: computed once with the node's own `seam_check` (`_seamless_helpers.py` of comfyui-pixaroma)
  // run by ComfyUI's Python (ComfyUI/.venv, torch), on float tensors = 8-bit value / 255, RGB (alpha dropped), for the
  // two formula pictures below.
  private static func noisy(_ x: Int, _ y: Int, _ c: Int) -> Int {
    (x * 7 + y * 13 + c * 29 + ((x * y) % 17) * 5 + (x / 4) * 11) % 256
  }

  @Test func theNumbersMatchThePythonOnANoisyPicture() throws {
    let r = SPSeam.check(TestImages.make(128, 96, Self.noisy))
    #expect(r.leftRight.status == .pass)
    #expect(abs(try #require(r.leftRight.ratio) - 0.68) < 1e-3)
    #expect(abs(try #require(r.leftRight.rank) - 1.0) < 1e-3)
    #expect(abs(try #require(r.leftRight.vsWorst) - 0.416) < 1e-3)
    #expect(r.upDown.status == .pass)
    #expect(abs(try #require(r.upDown.ratio) - 0.639) < 1e-3)
    #expect(abs(try #require(r.upDown.vsWorst) - 0.377) < 1e-3)
  }

  @Test func theNumbersMatchThePythonOnARamp() throws {
    let r = SPSeam.check(TestImages.make(128, 96) { x, _, _ in (x * 255) / 127 })
    #expect(r.leftRight.status == .fail)
    #expect(abs(try #require(r.leftRight.ratio) - 102.0) < 1e-3)
    #expect(abs(try #require(r.leftRight.rank)) < 1e-3)
    #expect(abs(try #require(r.leftRight.vsWorst) - 102.0) < 1e-3)
    // Up-down: nothing changes along y, so there is no normal line to compare with (the median is 0): the Python gives None.
    #expect(r.upDown.status == .pass)
    #expect(r.upDown.ratio == nil)
  }
}
