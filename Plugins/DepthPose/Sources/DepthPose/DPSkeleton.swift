import CoreGraphics

/// The 18 points of the OpenPose body model, in its order (the order is part of the format: do not change it).
enum DPJoint: Int, CaseIterable, Sendable {
  case nose, neck
  case rightShoulder, rightElbow, rightWrist
  case leftShoulder, leftElbow, leftWrist
  case rightHip, rightKnee, rightAnkle
  case leftHip, leftKnee, leftAnkle
  case rightEye, leftEye, rightEar, leftEar
}

/// A joint found in a picture: `x`, `y` in 0–1 with the origin at the top left, and how sure the detector is.
struct DPPoint: Equatable, Sendable {
  var x: Double
  var y: Double
  var confidence: Double
}

/// One person: the joints the detector found. Right and left are the person's own, as in Vision.
typealias DPPerson = [DPJoint: DPPoint]

/// What to draw for a person: the joints that can be trusted and the bones that have both ends.
enum DPSkeleton {
  /// Joints below this confidence are left out.
  static let minConfidence = 0.3

  /// The 17 bones of the OpenPose picture, as pairs of joints. Bone *i* is drawn in the colour *i*.
  static let bones: [(DPJoint, DPJoint)] = [
    (1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7), (1, 8), (8, 9), (9, 10), (1, 11), (11, 12), (12, 13), (1, 0),
    (0, 14), (14, 16), (0, 15), (15, 17),
  ].map { (DPJoint(rawValue: $0.0)!, DPJoint(rawValue: $0.1)!) }

  /// The usable joints, in the 0–1 space of the picture. A neck that is missing (or not trusted) is the midpoint of
  /// the shoulders when both are there.
  static func points(of person: DPPerson) -> [DPJoint: CGPoint] {
    var points: [DPJoint: CGPoint] = [:]
    for (joint, point) in person where point.confidence >= minConfidence {
      points[joint] = CGPoint(x: point.x, y: point.y)
    }
    if points[.neck] == nil, let right = points[.rightShoulder], let left = points[.leftShoulder] {
      points[.neck] = CGPoint(x: (right.x + left.x) / 2, y: (right.y + left.y) / 2)
    }
    return points
  }

  /// The bones whose two ends are usable, in the order of `bones`.
  static func drawableBones(of person: DPPerson) -> [(DPJoint, DPJoint)] {
    let points = points(of: person)
    return bones.filter { points[$0.0] != nil && points[$0.1] != nil }
  }
}
