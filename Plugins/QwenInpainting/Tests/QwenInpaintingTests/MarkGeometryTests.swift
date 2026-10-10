import CoreGraphics
import Testing

@testable import QwenInpainting

@Suite("Mark geometry")
struct MarkGeometryTests {
  let size = CGSize(width: 100, height: 100)
  func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

  @Test func aBoxIsTheRectangleBetweenTheCornersWhicheverWayItWasDragged() {
    let a = MarkGeometry.paths(for: Mark(tool: .box, color: .red, points: [pt(0.1, 0.1), pt(0.6, 0.6)]), in: size, imageWidth: 100)
    #expect(a.stroke.boundingBoxOfPath == CGRect(x: 10, y: 10, width: 50, height: 50) && a.fill == nil)
    let b = MarkGeometry.paths(for: Mark(tool: .box, color: .red, points: [pt(0.6, 0.6), pt(0.1, 0.1)]), in: size, imageWidth: 100)
    #expect(b.stroke.boundingBoxOfPath == a.stroke.boundingBoxOfPath)
  }

  @Test func aCircleFitsTheRectangleBetweenTheCorners() {
    let c = MarkGeometry.paths(for: Mark(tool: .circle, color: .red, points: [pt(0.1, 0.2), pt(0.5, 0.8)]), in: size, imageWidth: 100)
    let box = c.stroke.boundingBoxOfPath
    #expect(abs(box.minX - 10) < 0.01 && abs(box.minY - 20) < 0.01 && abs(box.width - 40) < 0.01 && abs(box.height - 60) < 0.01)
  }

  @Test func theHeadOfAnArrowIsAFilledTriangleAtTheTip() {
    let a = MarkGeometry.paths(
      for: Mark(tool: .arrow, color: .green, width: 10, points: [pt(0, 0.5), pt(1, 0.5)]), in: size, imageWidth: 100)
    let head = a.fill?.boundingBoxOfPath
    #expect(head != nil && abs(head!.maxX - 100) < 0.01)
    #expect(abs(head!.width - 40) < 0.01)  // max(10 × 4, 12), under 2/3 of 100
    #expect(abs(a.stroke.boundingBoxOfPath.maxX - 60) < 0.01)  // the shaft ends at the base of the head
  }

  @Test func theHeadOfAShortArrowIsAtMostTwoThirdsOfIt() {
    let a = MarkGeometry.paths(
      for: Mark(tool: .arrow, color: .green, width: 10, points: [pt(0, 0.5), pt(0.15, 0.5)]), in: size, imageWidth: 100)
    #expect(a.fill!.boundingBoxOfPath.width <= 10.001)
  }

  @Test func aSketchOfOnePointIsADotAndOfThreePointsPassesThroughTheEnds() {
    let dot = MarkGeometry.paths(for: Mark(tool: .sketch, color: .red, points: [pt(0.5, 0.5)]), in: size, imageWidth: 100)
    #expect(!dot.stroke.isEmpty)
    let path = MarkGeometry.paths(
      for: Mark(tool: .sketch, color: .red, points: [pt(0.1, 0.1), pt(0.5, 0.9), pt(0.9, 0.1)]), in: size, imageWidth: 100
    ).stroke
    var ends: [CGPoint] = []
    path.applyWithBlock { element in
      let e = element.pointee
      switch e.type {
      case .moveToPoint, .addLineToPoint: ends.append(e.points[0])
      case .addQuadCurveToPoint: ends.append(e.points[1])
      default: break
      }
    }
    #expect(ends.first == CGPoint(x: 10, y: 10) && ends.last == CGPoint(x: 90, y: 10))
  }

  @Test func theLineWidthFollowsTheScaleOfTheDrawing() {
    let a = MarkGeometry.paths(
      for: Mark(tool: .box, color: .red, width: 20, points: [pt(0, 0), pt(1, 1)]), in: CGSize(width: 500, height: 500), imageWidth: 1000)
    #expect(a.lineWidth == 10)
  }
}
