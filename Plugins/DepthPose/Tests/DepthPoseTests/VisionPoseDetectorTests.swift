import CoreGraphics
import Testing
import Vision

@testable import DepthPose

@Suite("VisionPoseDetector")
struct VisionPoseDetectorTests {
  @Test func everyVisionJointMapsExceptTheRoot() {
    let names: [(VNHumanBodyPoseObservation.JointName, DPJoint)] = [
      (.nose, .nose), (.neck, .neck), (.rightShoulder, .rightShoulder), (.rightElbow, .rightElbow),
      (.rightWrist, .rightWrist), (.leftShoulder, .leftShoulder), (.leftElbow, .leftElbow), (.leftWrist, .leftWrist),
      (.rightHip, .rightHip), (.rightKnee, .rightKnee), (.rightAnkle, .rightAnkle), (.leftHip, .leftHip),
      (.leftKnee, .leftKnee), (.leftAnkle, .leftAnkle), (.rightEye, .rightEye), (.leftEye, .leftEye),
      (.rightEar, .rightEar), (.leftEar, .leftEar),
    ]
    for (name, joint) in names { #expect(VisionPoseDetector.joint(for: name) == joint) }
    #expect(VisionPoseDetector.joint(for: .root) == nil)
  }

  @Test func theOriginMovesFromTheBottomToTheTop() {
    let person = VisionPoseDetector.person(from: [
      (.nose, CGPoint(x: 0.25, y: 0.9), 0.8), (.root, CGPoint(x: 0.5, y: 0.5), 0.9),
      (.neck, CGPoint(x: 0.5, y: 0.7), 0),
    ])
    let nose = person[.nose]
    #expect(nose != nil && abs(nose!.x - 0.25) < 1e-9 && abs(nose!.y - 0.1) < 1e-9)
    #expect(nose?.confidence == Double(Float(0.8)))
    #expect(person.count == 1)  // the root is not in the model and a joint with confidence 0 was not found
  }

  @Test func visionOnABlankImageFindsNoOne() async throws {
    let blank = Pictures.image(width: 128, height: 128, red: 0)
    let people = try await VisionPoseDetector().people(in: blank)
    #expect(people.isEmpty)
  }
}
