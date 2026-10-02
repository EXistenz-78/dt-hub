import CoreGraphics
import Foundation
import Testing

@testable import HubCore

struct StrokeSmootherTests {
  @Test func theFirstPointIsAPointAlone() {
    var smoother = StrokeSmoother()
    #expect(!smoother.isActive)
    #expect(smoother.add(CGPoint(x: 5, y: 7), spacing: 2) == [CGPoint(x: 5, y: 7)])
    #expect(smoother.isActive)
  }

  @Test func aStraightLineStaysStraight() {
    var smoother = StrokeSmoother()
    _ = smoother.add(CGPoint(x: 0, y: 10), spacing: 2)
    let points = smoother.add(CGPoint(x: 20, y: 10), spacing: 2) + smoother.add(CGPoint(x: 40, y: 10), spacing: 2)
    #expect(points.allSatisfy { abs($0.y - 10) < 0.0001 })
    // And it goes forward only.
    let xs = points.map(\.x)
    #expect(xs == xs.sorted())
  }

  @Test func theStrokePassesThroughTheMiddlesOfTheSegments() {
    var smoother = StrokeSmoother()
    _ = smoother.add(CGPoint(x: 0, y: 0), spacing: 2)
    let first = smoother.add(CGPoint(x: 40, y: 0), spacing: 2)
    #expect(first.first == CGPoint(x: 0, y: 0))
    #expect(first.last == CGPoint(x: 20, y: 0))
    let second = smoother.add(CGPoint(x: 40, y: 40), spacing: 2)
    #expect(second.first == CGPoint(x: 20, y: 0))
    #expect(second.last == CGPoint(x: 40, y: 20))
  }

  @Test func aCornerIsRoundedNotCutOrOvershot() {
    var smoother = StrokeSmoother()
    _ = smoother.add(CGPoint(x: 0, y: 0), spacing: 2)
    _ = smoother.add(CGPoint(x: 40, y: 0), spacing: 2)
    let curve = smoother.add(CGPoint(x: 40, y: 40), spacing: 2)
    // Between the two middles the curve bends toward the corner (40, 0) without reaching it.
    let nearest = curve.map { hypot($0.x - 40, $0.y - 0) }.min() ?? 0
    #expect(nearest > 1 && nearest < 10)
    #expect(curve.allSatisfy { $0.x <= 40.0001 && $0.y >= -0.0001 })
  }

  @Test func theCurveIsMadeOfShortSteps() {
    var smoother = StrokeSmoother()
    _ = smoother.add(CGPoint(x: 0, y: 0), spacing: 3)
    let curve = smoother.add(CGPoint(x: 300, y: 0), spacing: 3)
    for (a, b) in zip(curve, curve.dropFirst()) { #expect(hypot(b.x - a.x, b.y - a.y) <= 6) }
  }

  @Test func finishingTakesTheStrokeToTheLastPointAndStartsOver() {
    var smoother = StrokeSmoother()
    _ = smoother.add(CGPoint(x: 0, y: 0), spacing: 2)
    _ = smoother.add(CGPoint(x: 40, y: 0), spacing: 2)
    #expect(smoother.finish() == [CGPoint(x: 20, y: 0), CGPoint(x: 40, y: 0)])
    #expect(!smoother.isActive)
    #expect(smoother.finish().isEmpty)
    // A tap is a dot.
    var tap = StrokeSmoother()
    _ = tap.add(CGPoint(x: 3, y: 3), spacing: 2)
    #expect(tap.finish() == [CGPoint(x: 3, y: 3)])
  }
}
