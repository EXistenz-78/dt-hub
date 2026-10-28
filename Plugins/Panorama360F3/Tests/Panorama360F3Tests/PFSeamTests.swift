import CoreGraphics
import Foundation
import Testing

@testable import Panorama360F3

struct PFSeamTests {
  private func plan(_ width: Int, _ height: Int) throws -> PFSeamPlan {
    try PFSeam.plan(width: width, height: height).get()
  }

  // MARK: the plan

  @Test func planNumbers() throws {
    let a = try plan(2048, 1024)
    #expect(a.side == 1024 && a.quarter == 512 && a.barWidth == 256 && a.barX == 384 && a.feather == 32)
    let b = try plan(1536, 768)
    #expect(b.side == 768 && b.quarter == 384 && b.barWidth == 192 && b.barX == 288 && b.feather == 24)
    let c = try plan(2176, 1088)
    #expect(c.quarter == 544 && c.barWidth == 272 && c.feather == 34)
  }

  @Test func planReasons() {
    #expect(PFSeam.plan(width: 2048, height: 1000).failure == .sizeNotMultipleOf64)
    #expect(PFSeam.plan(width: 2048, height: 1536).failure == .notTwoToOne)
    #expect(PFSeam.plan(width: 8320, height: 4160).failure == .tooBig)
    #expect(PFSeam.plan(width: 0, height: 0).failure == .notTwoToOne)
    #expect(PFSeam.plan(width: 2112, height: 1024).failure == .notTwoToOne, "near 2:1 but not exactly: the square would not fit")
  }

  // MARK: the square

  @Test func squareJoinsTheTwoEnds() {
    let plan = PFSeamPlan(width: 128, height: 64)  // quarter 32, bar 16 from x 24
    let panorama = TestImages.coordinates(width: 128, height: 64)
    let square = try! #require(PFSeam.square(from: panorama, plan: plan, withBar: true))
    #expect(square.width == 64 && square.height == 64)
    #expect(TestImages.pixel(square, 0, 5) == TestImages.pixel(panorama, 96, 5))
    #expect(TestImages.pixel(square, 63, 5) == TestImages.pixel(panorama, 31, 5))
    #expect(TestImages.pixel(square, 23, 5) == TestImages.pixel(panorama, 119, 5))
    for x in 24..<40 { #expect(TestImages.pixel(square, x, 9) == (255, 255, 255)) }
    #expect(TestImages.pixel(square, 40, 5) == TestImages.pixel(panorama, 8, 5))
  }

  @Test func squareWithoutTheBarKeepsEveryColumn() {
    let plan = PFSeamPlan(width: 128, height: 64)
    let panorama = TestImages.coordinates(width: 128, height: 64)
    let square = try! #require(PFSeam.square(from: panorama, plan: plan, withBar: false))
    #expect(TestImages.pixel(square, 30, 7) == TestImages.pixel(panorama, 126, 7))
    #expect(TestImages.pixel(square, 32, 7) == TestImages.pixel(panorama, 0, 7))
    #expect(TestImages.pixel(square, 28, 7) != (255, 255, 255))
  }

  @Test func aPanoramaOfAnotherSizeGivesNoSquare() {
    let plan = PFSeamPlan(width: 128, height: 64)
    #expect(PFSeam.square(from: TestImages.coordinates(width: 100, height: 64), plan: plan, withBar: true) == nil)
  }

  // MARK: putting the result back

  @Test func mergeWithColourOffPutsBackTheTwoHalvesWithAFeather() throws {
    let plan = PFSeamPlan(width: 128, height: 64)  // quarter 32, feather 2
    let grey = TestImages.image(width: 128, height: 64) { _, _ in (100, 100, 100) }
    let result = TestImages.image(width: 64, height: 64) { x, _ in x < 32 ? (10, 20, 30) : (200, 100, 50) }
    let merged = try #require(PFSeam.merge(result: result, into: grey, plan: plan, matchingColour: false))
    #expect(merged.width == 128 && merged.height == 64)
    #expect(TestImages.pixel(merged, 127, 10) == (10, 20, 30))
    #expect(TestImages.pixel(merged, 0, 10) == (200, 100, 50))
    #expect(TestImages.pixel(merged, 96, 10) == (100, 100, 100), "the inner edge of the right end is the original")
    #expect(TestImages.pixel(merged, 98, 10) == (10, 20, 30), "from `feather` pixels in it is the result")
    #expect(TestImages.pixel(merged, 31, 10) == (100, 100, 100), "the inner edge of the left end is the original")
    #expect(TestImages.pixel(merged, 29, 10) == (200, 100, 50))
    #expect(TestImages.pixel(merged, 64, 10) == (100, 100, 100), "the middle of the panorama is untouched")
  }

  @Test func mergeOfTheUntouchedSquareChangesNothing() throws {
    let plan = PFSeamPlan(width: 128, height: 64)
    let panorama = TestImages.coordinates(width: 128, height: 64)
    let result = try #require(PFSeam.square(from: panorama, plan: plan, withBar: false))
    let merged = try #require(PFSeam.merge(result: result, into: panorama, plan: plan))
    for (x, y) in [(0, 0), (5, 9), (31, 40), (64, 10), (100, 20), (127, 63)] {
      let a = TestImages.pixel(merged, x, y), b = TestImages.pixel(panorama, x, y)
      #expect(abs(Int(a.0) - Int(b.0)) <= 1 && abs(Int(a.1) - Int(b.1)) <= 1 && abs(Int(a.2) - Int(b.2)) <= 1)
    }
  }

  @Test func aResultOfAnotherSizeIsRefused() {
    let plan = PFSeamPlan(width: 128, height: 64)
    let panorama = TestImages.coordinates(width: 128, height: 64)
    #expect(PFSeam.merge(result: TestImages.coordinates(width: 60, height: 60), into: panorama, plan: plan) == nil)
  }

  // MARK: colour

  @Test func matchColourBringsMeanAndSpreadTowardsTheReference() throws {
    let reference = TestImages.image(width: 64, height: 64) { x, y in
      (UInt8(20 + (x * 37 + y * 91) % 180), UInt8(30 + (x * 53 + y * 17) % 160), UInt8(10 + (x * 11 + y * 71) % 200))
    }
    let dull = TestImages.image(width: 64, height: 64) { x, y in
      let p = TestImages.pixel(reference, x, y)
      return (UInt8(Int(p.0) * 2 / 5 + 10), UInt8(Int(p.1) * 2 / 5 + 10), UInt8(Int(p.2) * 2 / 5 + 10))
    }
    let matched = try #require(PFSeam.matchColour(dull, to: reference))
    func stats(_ image: CGImage) -> (mean: Double, spread: Double) {
      var values: [Double] = []
      for y in stride(from: 0, to: 64, by: 2) {
        for x in stride(from: 0, to: 64, by: 2) {
          let p = TestImages.pixel(image, x, y)
          values.append((Double(p.0) + Double(p.1) + Double(p.2)) / 3)
        }
      }
      let mean = values.reduce(0, +) / Double(values.count)
      let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
      return (mean, variance.squareRoot())
    }
    let before = stats(dull), after = stats(matched), target = stats(reference)
    #expect(abs(before.mean - target.mean) > 15, "the test picture really differs")
    #expect(abs(after.mean - target.mean) <= 10)
    #expect(after.spread / target.spread > 0.85 && after.spread / target.spread < 1.15)
  }
}

extension Result {
  fileprivate var failure: Failure? {
    if case .failure(let error) = self { return error }
    return nil
  }
}
