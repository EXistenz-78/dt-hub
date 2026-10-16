import CoreGraphics
import Foundation

/// Turns the 133 keypoints of COCO-WholeBody (what DWPose and RTMW give) into a figure of the OpenPose layout: the 18
/// body joints (the neck is made), the 68 points of the face and 21 of each hand. The feet are not used.
enum DPWholeBody {
  /// A figure whose body joints (the first 17 keypoints) score less than this on average is not a person.
  static let minBodyScore: Float = 0.35

  /// The COCO index of each OpenPose joint (right and left are the person's own, as in COCO).
  private static let cocoIndex: [DPJoint: Int] = [
    .nose: 0, .leftEye: 1, .rightEye: 2, .leftEar: 3, .rightEar: 4, .leftShoulder: 5, .rightShoulder: 6,
    .leftElbow: 7, .rightElbow: 8, .leftWrist: 9, .rightWrist: 10, .leftHip: 11, .rightHip: 12, .leftKnee: 13,
    .rightKnee: 14, .leftAnkle: 15, .rightAnkle: 16,
  ]

  /// `peaks` are the 133 decoded peaks; the points come out as fractions of the picture (origin at the top left).
  static func figure(peaks: [DPSimCCPeak], crop: DPCrop, imageWidth: Int, imageHeight: Int) -> DPFigure {
    guard peaks.count >= DPSimCC.wholeBodyKeypoints, imageWidth > 0, imageHeight > 0 else { return DPFigure(body: [:]) }
    func point(_ peak: DPSimCCPeak) -> DPPoint {
      let location = crop.imagePoint(binX: Double(peak.x), binY: Double(peak.y))
      return DPPoint(
        x: Double(location.x) / Double(imageWidth), y: Double(location.y) / Double(imageHeight),
        confidence: peak.isFound ? Double(peak.score) : 0)
    }
    var body: DPPerson = [:]
    for (joint, index) in cocoIndex { body[joint] = point(peaks[index]) }
    if let left = body[.leftShoulder], let right = body[.rightShoulder] {
      body[.neck] = DPPoint(
        x: (left.x + right.x) / 2, y: (left.y + right.y) / 2, confidence: min(left.confidence, right.confidence))
    }
    return DPFigure(
      body: body, face: peaks[23..<91].map(point), leftHand: peaks[91..<112].map(point),
      rightHand: peaks[112..<133].map(point))
  }

  /// The mean score of the 17 body keypoints.
  static func bodyScore(of peaks: [DPSimCCPeak]) -> Float {
    let body = peaks.prefix(17)
    guard !body.isEmpty else { return 0 }
    return body.reduce(0) { $0 + $1.score } / Float(body.count)
  }
}
