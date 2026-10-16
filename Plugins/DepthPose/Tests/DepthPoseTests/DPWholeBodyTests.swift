import CoreGraphics
import Testing

@testable import DepthPose

@Suite("DPWholeBody")
struct DPWholeBodyTests {
  /// 133 peaks where the score of the peak with index *i* is `0.1 + 0.001·i` (so a score tells which index it came
  /// from), all at the bin of the crop centre.
  private func peaks(body: Float? = nil, found: Bool = true) -> [DPSimCCPeak] {
    (0..<133).map { index in
      var score = 0.1 + 0.001 * Float(index)
      if let body, index < 17 { score = body }
      return DPSimCCPeak(x: 288, y: 384, score: found ? score : 0)
    }
  }

  private let crop = DPCrop(box: CGRect(x: 100, y: 50, width: 60, height: 150))

  private func figure(_ peaks: [DPSimCCPeak]) -> DPFigure {
    DPWholeBody.figure(peaks: peaks, crop: crop, imageWidth: 400, imageHeight: 300)
  }

  private func index(of score: Double) -> Int { Int(((score - 0.1) / 0.001).rounded()) }

  @Test func eachCocoIndexGoesToTheRightOpenPoseJoint() {
    let body = figure(peaks()).body
    let expected: [DPJoint: Int] = [
      .nose: 0, .rightEye: 2, .leftEye: 1, .rightEar: 4, .leftEar: 3, .rightShoulder: 6, .leftShoulder: 5,
      .rightElbow: 8, .leftElbow: 7, .rightWrist: 10, .leftWrist: 9, .rightHip: 12, .leftHip: 11, .rightKnee: 14,
      .leftKnee: 13, .rightAnkle: 16, .leftAnkle: 15,
    ]
    for (joint, cocoIndex) in expected {
      #expect(body[joint].map { index(of: $0.confidence) } == cocoIndex, "\(joint)")
    }
  }

  @Test func theNeckIsTheMidpointOfTheShouldersWithTheLowerScore() {
    var all = peaks()
    // Right shoulder (6) and left shoulder (5) at different places and scores.
    all[5] = DPSimCCPeak(x: 288 - 40, y: 384, score: 0.9)
    all[6] = DPSimCCPeak(x: 288 + 40, y: 384, score: 0.5)
    let body = figure(all).body
    let left = crop.imagePoint(binX: 248, binY: 384), right = crop.imagePoint(binX: 328, binY: 384)
    let neck = body[.neck]
    #expect(neck != nil)
    #expect(abs((neck?.x ?? 0) - Double((left.x + right.x) / 2) / 400) < 1e-6)
    #expect(abs((neck?.y ?? 0) - Double((left.y + right.y) / 2) / 300) < 1e-6)
    #expect(abs((neck?.confidence ?? 0) - 0.5) < 1e-6)
  }

  @Test func theFaceIsIndices23To90() {
    let face = figure(peaks()).face
    #expect(face.count == 68)
    #expect(index(of: face[0].confidence) == 23 && index(of: face[67].confidence) == 90)
  }

  @Test func handsAreTheTwoBlocksOf21() {
    let result = figure(peaks())
    #expect(result.leftHand.count == 21 && result.rightHand.count == 21)
    #expect(index(of: result.leftHand[0].confidence) == 91 && index(of: result.leftHand[20].confidence) == 111)
    #expect(index(of: result.rightHand[0].confidence) == 112 && index(of: result.rightHand[20].confidence) == 132)
  }

  @Test func theFeetAreNotUsed() {
    let result = figure(peaks())
    let used = Set(
      result.body.values.map { index(of: $0.confidence) } + result.face.map { index(of: $0.confidence) }
        + result.leftHand.map { index(of: $0.confidence) } + result.rightHand.map { index(of: $0.confidence) })
    for foot in 17...22 { #expect(!used.contains(foot), "index \(foot)") }
  }

  @Test func coordinatesAreNormalisedOnThePicture() {
    let point = figure(peaks()).body[.nose]
    // Every peak is at the centre bin: the centre of the box (130, 125) over a 400×300 picture.
    #expect(abs((point?.x ?? 0) - 130.0 / 400) < 1e-6 && abs((point?.y ?? 0) - 125.0 / 300) < 1e-6)
  }

  @Test func aNotFoundPeakHasZeroConfidence() {
    let result = figure(peaks(found: false))
    #expect(result.body.values.allSatisfy { $0.confidence == 0 })
    #expect(result.face.allSatisfy { $0.confidence == 0 })
  }

  @Test func theBodyScoreIsTheMeanOfTheFirst17() {
    #expect(abs(DPWholeBody.bodyScore(of: peaks(body: 0.6)) - 0.6) < 1e-6)
    #expect(DPWholeBody.bodyScore(of: []) == 0)
  }

  @Test func tooFewPeaksGiveAnEmptyFigure() {
    let result = figure(Array(peaks().prefix(50)))
    #expect(result.body.isEmpty && result.face.isEmpty && result.leftHand.isEmpty && result.rightHand.isEmpty)
  }

  @Test func theThresholdIsTheOneOfTheSpec() {
    #expect(DPWholeBody.minBodyScore == 0.35)
  }
}
