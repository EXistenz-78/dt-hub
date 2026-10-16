import CoreGraphics
import Vision

/// Finds the people in a picture and their joints.
protocol DPPoseDetecting: Sendable {
  func people(in image: CGImage) async throws -> [DPPerson]
}

/// The body pose of Apple's Vision framework (2D, every person in the picture).
struct VisionPoseDetector: DPPoseDetecting {
  func people(in image: CGImage) async throws -> [DPPerson] {
    return try await Task.detached(priority: .userInitiated) {
      let request = VNDetectHumanBodyPoseRequest()
      try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
      return try (request.results ?? []).map { observation in
        Self.person(
          from: try observation.recognizedPoints(.all).map { ($0.key, $0.value.location, $0.value.confidence) })
      }
    }.value
  }

  /// The joint of the model for a Vision name; nil for the root, which OpenPose does not have.
  static func joint(for name: VNHumanBodyPoseObservation.JointName) -> DPJoint? {
    switch name {
    case .nose: .nose
    case .neck: .neck
    case .rightShoulder: .rightShoulder
    case .rightElbow: .rightElbow
    case .rightWrist: .rightWrist
    case .leftShoulder: .leftShoulder
    case .leftElbow: .leftElbow
    case .leftWrist: .leftWrist
    case .rightHip: .rightHip
    case .rightKnee: .rightKnee
    case .rightAnkle: .rightAnkle
    case .leftHip: .leftHip
    case .leftKnee: .leftKnee
    case .leftAnkle: .leftAnkle
    case .rightEye: .rightEye
    case .leftEye: .leftEye
    case .rightEar: .rightEar
    case .leftEar: .leftEar
    default: nil
    }
  }

  /// One person from Vision's points (origin at the bottom left): the origin moves to the top, the root and the
  /// joints that were not found (confidence 0) are left out.
  static func person(from points: [(VNHumanBodyPoseObservation.JointName, CGPoint, Float)]) -> DPPerson {
    var person: DPPerson = [:]
    for (name, location, confidence) in points where confidence > 0 {
      guard let joint = joint(for: name) else { continue }
      person[joint] = DPPoint(x: Double(location.x), y: 1 - Double(location.y), confidence: Double(confidence))
    }
    return person
  }
}
