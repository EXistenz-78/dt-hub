import CoreGraphics
import Foundation
import Testing

@testable import DepthPose

/// Face and hands of the DWPose picture, on a 200×200 picture (the thickness of the body is 3 pixels there: hand
/// joints have a radius of 3, hand edges a width of 2, face dots a radius of 2).
@Suite("DPPoseRenderer, face and hands")
struct DPFullPoseRendererTests {
  private func point(_ x: Double, _ y: Double, _ confidence: Double = 1) -> DPPoint {
    DPPoint(x: x, y: y, confidence: confidence)
  }

  private func px(_ x: Double, _ y: Double) -> DPPoint { point(x / 200, y / 200) }

  private func near(_ a: [Int], _ b: [Int], _ tolerance: Int = 3) -> Bool {
    zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
  }

  /// The body of the older tests: neck at (100,100), nose above, shoulders left and right.
  private var body: DPPerson {
    [
      .nose: point(0.5, 0.2), .neck: point(0.5, 0.5), .rightShoulder: point(0.25, 0.5), .leftShoulder: point(0.75, 0.5),
    ]
  }

  /// 21 points in a zigzag: point *i* at (20 + 8i, 150 + 20·(i mod 2)).
  private var zigzagHand: [DPPoint] {
    (0..<21).map { (index: Int) -> DPPoint in
      let x = Double(20 + 8 * index)
      let y = Double(150 + 20 * (index % 2))
      return px(x, y)
    }
  }

  private func render(_ figures: [DPFigure]) throws -> CGImage {
    try #require(DPPoseRenderer.render(figures, width: 200, height: 200))
  }

  @Test func theHueOfAnEdgeFollowsItsIndex() {
    #expect(DPPoseRenderer.hsv(0) == (255, 0, 0))
    #expect(DPPoseRenderer.hsv(0.5) == (0, 255, 255))
    let quarter = DPPoseRenderer.hsv(0.25)
    #expect(abs(Int(quarter.0) - 128) <= 1 && quarter.1 == 255 && quarter.2 == 0)
    #expect(DPPoseRenderer.handEdges.count == 20)
    #expect(DPPoseRenderer.handEdges[0] == (0, 1) && DPPoseRenderer.handEdges[4] == (0, 5))
    #expect(DPPoseRenderer.handEdges[19] == (19, 20))
  }

  @Test func handEdgesTakeTheColourOfTheirHue() throws {
    let image = try render([DPFigure(body: body, leftHand: zigzagHand)])
    #expect(near(Pictures.pixel(image, 24, 160), [255, 0, 0]), "edge 0, hue 0")
    #expect(near(Pictures.pixel(image, 104, 160), [0, 255, 255]), "edge 10 (points 10 and 11), hue 0.5")
  }

  @Test func handPointsAreBlue() throws {
    let image = try render([DPFigure(body: body, rightHand: zigzagHand)])
    #expect(near(Pictures.pixel(image, 100, 150), [0, 0, 255]))
  }

  @Test func faceDotsAreWhite() throws {
    let face = (0..<20).map { (index: Int) -> DPPoint in px(Double(100 + 4 * index), 20) }
    let image = try render([DPFigure(body: body, face: face)])
    #expect(near(Pictures.pixel(image, 100, 20), [255, 255, 255]))
    #expect(near(Pictures.pixel(image, 140, 20), [255, 255, 255]))
    #expect(Pictures.pixel(image, 190, 20) == [0, 0, 0], "beyond the last dot (x = 176)")
  }

  @Test func handsAreOverTheBonesAndTheFaceIsOverTheHands() throws {
    // A hand edge (cyan, points 10 and 11) crosses the neck-shoulder bone of the body at (75,100); a face dot sits on it.
    var hand = [DPPoint](repeating: point(0, 0, 0), count: 21)
    hand[10] = px(75, 70)
    hand[11] = px(75, 130)
    var face = [DPPoint](repeating: point(0, 0, 0), count: 68)
    for index in 0..<10 { face[index] = px(75, 85) }
    let image = try render([DPFigure(body: body, face: face, leftHand: hand)])
    #expect(near(Pictures.pixel(image, 75, 100), [0, 255, 255]), "hand over the bone, full colour")
    #expect(near(Pictures.pixel(image, 75, 85), [255, 255, 255]), "face over the hand")
  }

  @Test func pointsBelowTheThresholdAreNotDrawn() throws {
    let weak = (0..<20).map { (index: Int) -> DPPoint in point(Double(100 + 4 * index) / 200, 0.1, 0.29) }
    let image = try render([DPFigure(body: body, face: weak)])
    #expect(Pictures.pixel(image, 100, 20) == [0, 0, 0])
  }

  @Test func aHandNeedsFivePointsAndAFaceTen() {
    func points(_ count: Int) -> [DPPoint] {
      (0..<21).map { (index: Int) -> DPPoint in index < count ? point(Double(index) / 30, 0.5) : point(0, 0, 0) }
    }
    func face(_ count: Int) -> [DPPoint] {
      (0..<68).map { (index: Int) -> DPPoint in index < count ? point(Double(index) / 90, 0.2) : point(0, 0, 0) }
    }
    #expect(!DPPoseRenderer.isDrawable(DPFigure(body: [:], leftHand: points(4))))
    #expect(DPPoseRenderer.isDrawable(DPFigure(body: [:], leftHand: points(5))))
    #expect(DPPoseRenderer.isDrawable(DPFigure(body: [:], rightHand: points(5))))
    #expect(!DPPoseRenderer.isDrawable(DPFigure(body: [:], face: face(9))))
    #expect(DPPoseRenderer.isDrawable(DPFigure(body: [:], face: face(10))))
    #expect(DPPoseRenderer.isDrawable(DPFigure(body: body)))
    #expect(!DPPoseRenderer.isDrawable(DPFigure(body: [:])))
  }

  @Test func aFigureWithOnlyAFaceIsDrawnAndOneWithAWeakHandIsNot() throws {
    let face = (0..<20).map { (index: Int) -> DPPoint in px(Double(60 + 4 * index), 40) }
    #expect(DPPoseRenderer.render([DPFigure(body: [:], face: face)], width: 200, height: 200) != nil)
    let weakHand = (0..<21).map { (index: Int) -> DPPoint in point(Double(index) / 30, 0.5, 0.1) }
    #expect(DPPoseRenderer.render([DPFigure(body: [:], leftHand: weakHand)], width: 200, height: 200) == nil)
  }

  @Test func pointsOutsideThePictureAreSkippedWithoutAnError() throws {
    let outside = (0..<20).map { (index: Int) -> DPPoint in point(index % 2 == 0 ? -0.5 : 1.5, Double(index) / 20) }
    let farHand = [DPPoint](repeating: point(-2, 3), count: 21)
    let image = try render([DPFigure(body: body, face: outside, leftHand: farHand)])
    #expect(image.width == 200 && image.height == 200)
  }

  @Test func withoutFaceAndHandsThePictureIsTheOldOne() throws {
    let newWay = try #require(DPPoseRenderer.render([DPFigure(body: body)], width: 200, height: 200))
    let oldWay = try #require(DPPoseRenderer.render([body], width: 200, height: 200))
    #expect(DPPoseRenderer.pngData(newWay) == DPPoseRenderer.pngData(oldWay))
  }
}
