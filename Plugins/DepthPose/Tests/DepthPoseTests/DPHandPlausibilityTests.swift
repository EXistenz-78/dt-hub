import Testing

@testable import DepthPose

/// A hand the model "sees" even when it is not in the picture must not be drawn: it is kept only when most of its
/// points are sure and its size and place fit the body.
@Suite("DPWholeBody, plausible hands")
struct DPHandPlausibilityTests {
  /// A 1000×1000 picture: shoulders 200 px apart, the left wrist at (650, 500).
  private func body(wristConfidence: Double = 0.8, shoulders: Bool = true) -> DPPerson {
    var body: DPPerson = [.leftWrist: DPPoint(x: 0.65, y: 0.5, confidence: wristConfidence)]
    if shoulders {
      body[.leftShoulder] = DPPoint(x: 0.6, y: 0.3, confidence: 0.9)
      body[.rightShoulder] = DPPoint(x: 0.4, y: 0.3, confidence: 0.9)
    }
    return body
  }

  /// 21 points in a grid whose first point (the wrist) is at `centre` (px), `spread` px wide and tall, the first `sure` of them with a high score.
  private func hand(centre: (Double, Double) = (650, 500), spread: Double = 60, sure: Int = 21) -> [DPPoint] {
    (0..<21).map { (i: Int) -> DPPoint in
      let x = centre.0 + spread * Double(i % 5) / 4
      let y = centre.1 + spread * Double(i / 5) / 4
      return DPPoint(x: x / 1000, y: y / 1000, confidence: i < sure ? 0.7 : 0.4)
    }
  }

  private func filtered(_ figure: DPFigure) -> DPFigure {
    DPWholeBody.droppingImplausibleHands(figure, imageWidth: 1000, imageHeight: 1000)
  }

  @Test func aSureCompactHandNearTheWristIsKept() {
    let figure = DPFigure(body: body(), leftHand: hand())
    #expect(filtered(figure).leftHand.count == 21)
  }

  @Test func aHandNeedsFifteenPointsAtHalfConfidence() {
    #expect(filtered(DPFigure(body: body(), leftHand: hand(sure: 15))).leftHand.count == 21)
    #expect(filtered(DPFigure(body: body(), leftHand: hand(sure: 14))).leftHand.isEmpty)
  }

  @Test func aHandTooBigForTheBodyIsDropped() {
    // 200 px shoulders: the biggest hand allowed is 160 px.
    #expect(filtered(DPFigure(body: body(), leftHand: hand(spread: 150))).leftHand.count == 21)
    #expect(filtered(DPFigure(body: body(), leftHand: hand(spread: 170))).leftHand.isEmpty)
  }

  @Test func aHandFarFromTheWristIsDropped() {
    // Allowed: the hand's wrist point within 100 px (half the shoulders) of the body wrist.
    #expect(filtered(DPFigure(body: body(), leftHand: hand(centre: (650, 560)))).leftHand.count == 21)
    #expect(filtered(DPFigure(body: body(), leftHand: hand(centre: (650, 700)))).leftHand.isEmpty)
  }

  @Test func withoutAWristOrShouldersOnlyTheScoreCounts() {
    let far = hand(centre: (100, 900), spread: 500)
    #expect(filtered(DPFigure(body: body(wristConfidence: 0.1, shoulders: false), leftHand: far)).leftHand.count == 21)
  }

  @Test func everythingElseIsUntouched() {
    let face = (0..<68).map { (i: Int) -> DPPoint in DPPoint(x: Double(i) / 100, y: 0.1, confidence: 0.9) }
    let figure = DPFigure(body: body(), face: face, leftHand: hand(sure: 3), rightHand: hand(sure: 3))
    let result = filtered(figure)
    #expect(result.body == figure.body && result.face == figure.face)
    #expect(result.leftHand.isEmpty && result.rightHand.isEmpty)
  }
}
