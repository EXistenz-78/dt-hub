import CoreGraphics
import Foundation
import Vision

/// Finds the people in a picture and draws from them the whole-body figure (body, face, hands).
protocol DPFullPoseDetecting: Sendable {
  func figures(in image: CGImage) async throws -> [DPFigure]
}

/// The whole-body network: a 288×384 RGB crop in, the two SimCC vectors of the 133 keypoints out (`keypoints × bins`,
/// flattened).
protocol DPPoseNetwork: Sendable {
  func simcc(for crop: CGImage) throws -> (x: [Float], y: [Float])
}

/// Where the people are: boxes in pixels of the picture, origin at the top left.
protocol DPPersonBoxFinding: Sendable {
  func boxes(in image: CGImage) async throws -> [CGRect]
}

/// The person boxes of Apple's Vision framework (whole bodies). It finds nothing in an illustration.
struct VisionPersonBoxFinder: DPPersonBoxFinding {
  func boxes(in image: CGImage) async throws -> [CGRect] {
    try await Task.detached(priority: .userInitiated) {
      let request = VNDetectHumanRectanglesRequest()
      request.upperBodyOnly = false
      try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
      let width = Double(image.width), height = Double(image.height)
      return (request.results ?? []).map { observation in
        let box = observation.boundingBox  // fractions, origin at the bottom left
        return CGRect(
          x: box.minX * width, y: (1 - box.maxY) * height, width: box.width * width, height: box.height * height)
      }
    }.value
  }
}

/// DWPose: a crop of each person goes to the network, the keypoints come back as a figure. With no person box found
/// the whole picture is tried as one (an illustration); a figure that scores too low is not a person.
struct DWPoseDetector: DPFullPoseDetecting {
  /// At most this many people, the biggest boxes first.
  static let maxPeople = 12

  var network: any DPPoseNetwork
  var boxFinder: any DPPersonBoxFinding

  func figures(in image: CGImage) async throws -> [DPFigure] {
    var boxes = try await boxFinder.boxes(in: image)
    if boxes.isEmpty { boxes = [CGRect(x: 0, y: 0, width: image.width, height: image.height)] }
    return try figures(in: image, boxes: boxes)
  }

  /// The figures of the given boxes (the finder is not asked): the biggest `maxPeople` boxes, biggest first.
  func figures(in image: CGImage, boxes: [CGRect]) throws -> [DPFigure] {
    let chosen = boxes.sorted { $0.width * $0.height > $1.width * $1.height }.prefix(Self.maxPeople)
    var figures: [DPFigure] = []
    for box in chosen {
      let crop = DPCrop(box: box)
      guard let cropped = crop.render(image) else { continue }
      let vectors = try network.simcc(for: cropped)
      let peaks = DPSimCC.decode(x: vectors.x, y: vectors.y)
      // The mean of 17 floats can land a hair under the threshold it equals: a tolerance of 1e-5.
      guard DPWholeBody.bodyScore(of: peaks) + 1e-5 >= DPWholeBody.minBodyScore else { continue }
      let figure = DPWholeBody.figure(peaks: peaks, crop: crop, imageWidth: image.width, imageHeight: image.height)
      figures.append(DPWholeBody.droppingImplausibleHands(figure, imageWidth: image.width, imageHeight: image.height))
    }
    return figures
  }
}
