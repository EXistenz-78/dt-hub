import Foundation

/// Where the model put one keypoint: the bin of the maximum of each SimCC axis (two bins per pixel of the crop), and
/// how sure it is.
struct DPSimCCPeak: Equatable, Sendable {
  var x: Int
  var y: Int
  var score: Float
  /// A keypoint with a score of zero or less is not there.
  var isFound: Bool { score > 0 }
}

/// Decodes the two SimCC outputs of an RTMPose-family model (RTMW, DWPose).
enum DPSimCC {
  /// The keypoints of COCO-WholeBody: 17 of the body, 6 of the feet, 68 of the face, 21 of each hand.
  static let wholeBodyKeypoints = 133

  /// `x` and `y` are the flattened `keypoints × bins` vectors (the bin counts follow from their length). Each peak is
  /// the argmax of its rows; the score is the mean of the two maxima.
  static func decode(x: [Float], y: [Float], keypoints: Int = wholeBodyKeypoints) -> [DPSimCCPeak] {
    guard keypoints > 0, !x.isEmpty, !y.isEmpty, x.count % keypoints == 0, y.count % keypoints == 0 else { return [] }
    let xBins = x.count / keypoints, yBins = y.count / keypoints
    var peaks: [DPSimCCPeak] = []
    peaks.reserveCapacity(keypoints)
    for keypoint in 0..<keypoints {
      let (xBin, xMax) = argmax(x, from: keypoint * xBins, count: xBins)
      let (yBin, yMax) = argmax(y, from: keypoint * yBins, count: yBins)
      peaks.append(DPSimCCPeak(x: xBin, y: yBin, score: 0.5 * (xMax + yMax)))
    }
    return peaks
  }

  private static func argmax(_ values: [Float], from start: Int, count: Int) -> (bin: Int, value: Float) {
    var best = 0
    var bestValue = values[start]
    for bin in 1..<max(1, count) where values[start + bin] > bestValue {
      best = bin
      bestValue = values[start + bin]
    }
    return (best, bestValue)
  }
}
