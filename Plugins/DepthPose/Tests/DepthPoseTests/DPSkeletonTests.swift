import CoreGraphics
import Testing

@testable import DepthPose

@Suite("DPSkeleton")
struct DPSkeletonTests {
  private func point(_ x: Double, _ y: Double, _ confidence: Double = 1) -> DPPoint {
    DPPoint(x: x, y: y, confidence: confidence)
  }

  private func pairs(_ bones: [(DPJoint, DPJoint)]) -> [[Int]] { bones.map { [$0.0.rawValue, $0.1.rawValue] } }

  @Test func bonesAreTheSeventeenOfOpenPose() {
    #expect(
      pairs(DPSkeleton.bones) == [
        [1, 2], [1, 5], [2, 3], [3, 4], [5, 6], [6, 7], [1, 8], [8, 9], [9, 10], [1, 11], [11, 12], [12, 13], [1, 0],
        [0, 14], [14, 16], [0, 15], [15, 17],
      ])
  }

  @Test func theJointsAreInTheOrderOfOpenPose() {
    #expect(DPJoint.allCases.count == 18)
    #expect(DPJoint.nose.rawValue == 0 && DPJoint.neck.rawValue == 1 && DPJoint.rightShoulder.rawValue == 2)
    #expect(DPJoint.leftEar.rawValue == 17)
  }

  @Test func jointBelowThresholdIsDropped() {
    let person: DPPerson = [.nose: point(0.5, 0.1, 0.29), .neck: point(0.5, 0.2, 0.3)]
    let points = DPSkeleton.points(of: person)
    #expect(points[.nose] == nil)
    #expect(points[.neck] == CGPoint(x: 0.5, y: 0.2))
  }

  @Test func missingNeckIsTheMidpointOfTheShoulders() {
    let person: DPPerson = [.rightShoulder: point(0.4, 0.3), .leftShoulder: point(0.6, 0.5)]
    let neck = DPSkeleton.points(of: person)[.neck]
    #expect(neck != nil && abs(neck!.x - 0.5) < 1e-9 && abs(neck!.y - 0.4) < 1e-9)
  }

  @Test func neckWithTooLittleConfidenceIsReplacedByTheMidpoint() {
    let person: DPPerson = [.neck: point(0.9, 0.9, 0.1), .rightShoulder: point(0.4, 0.3), .leftShoulder: point(0.6, 0.3)]
    #expect(DPSkeleton.points(of: person)[.neck] == CGPoint(x: 0.5, y: 0.3))
  }

  @Test func withOnlyOneShoulderThereIsNoNeck() {
    #expect(DPSkeleton.points(of: [.rightShoulder: point(0.4, 0.3)])[.neck] == nil)
  }

  @Test func existingNeckIsKept() {
    let person: DPPerson = [.neck: point(0.1, 0.2), .rightShoulder: point(0.4, 0.3), .leftShoulder: point(0.6, 0.3)]
    #expect(DPSkeleton.points(of: person)[.neck] == CGPoint(x: 0.1, y: 0.2))
  }

  @Test func rightAndLeftAreNotSwapped() {
    let points = DPSkeleton.points(of: [.rightShoulder: point(0.2, 0.2), .leftShoulder: point(0.8, 0.2)])
    #expect(points[.rightShoulder] == CGPoint(x: 0.2, y: 0.2))
    #expect(points[.leftShoulder] == CGPoint(x: 0.8, y: 0.2))
  }

  @Test func aBoneNeedsBothEnds() {
    let person: DPPerson = [.rightShoulder: point(0.4, 0.3), .rightElbow: point(0.4, 0.5), .rightWrist: point(0.4, 0.7, 0.1)]
    // The neck is not there either (one shoulder only): neck-shoulder is not drawable, shoulder-elbow is.
    #expect(pairs(DPSkeleton.drawableBones(of: person)) == [[2, 3]])
  }

  @Test func aPersonWithOneJointHasNoBones() {
    #expect(DPSkeleton.drawableBones(of: [.nose: point(0.5, 0.5)]).isEmpty)
  }
}
