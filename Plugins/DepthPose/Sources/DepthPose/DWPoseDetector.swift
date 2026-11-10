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
    let boxes = try await boxFinder.boxes(in: image)
    if boxes.isEmpty { return try figuresWithoutBoxes(in: image) }
    return try figures(in: image, boxes: boxes)
  }

  /// Vision found nobody (an illustration, an odd pose): the whole picture is the first box. A person who fills a part of a
  /// wide picture shrinks to a few dozen pixels in the 288×384 crop and scores too low, so the points the network did find
  /// give a tighter box and the crop is made again (twice at most).
  func figuresWithoutBoxes(in image: CGImage) throws -> [DPFigure] {
    var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    for _ in 0...Self.refinements {
      let crop = DPCrop(box: box)
      guard let cropped = crop.render(image) else { return [] }
      let vectors = try network.simcc(for: cropped)
      let peaks = DPSimCC.decode(x: vectors.x, y: vectors.y)
      if DPWholeBody.bodyScore(of: peaks) + 1e-5 >= DPWholeBody.minBodyScore {
        let figure = DPWholeBody.figure(peaks: peaks, crop: crop, imageWidth: image.width, imageHeight: image.height)
        return [DPWholeBody.droppingImplausibleHands(figure, imageWidth: image.width, imageHeight: image.height)]
      }
      guard let next = Self.box(around: peaks, in: crop, image: image, smallerThan: box) else { return [] }
      box = next
    }
    return []
  }

  /// How many times a failed crop of the whole picture is made again around the points found.
  static let refinements = 2
  /// A body point counts for the new box from this score (lower than the one that accepts a figure).
  static let hintScore: Float = 0.25

  /// The box of the body points the network was fairly sure of, in pixels of the picture; nil when there are too few of
  /// them or the box is not clearly smaller than the one tried.
  static func box(around peaks: [DPSimCCPeak], in crop: DPCrop, image: CGImage, smallerThan old: CGRect) -> CGRect? {
    let points = peaks.prefix(17).filter { $0.score >= hintScore }.map { crop.imagePoint(binX: Double($0.x), binY: Double($0.y)) }
    guard points.count >= 4 else { return nil }
    let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
    let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
    // The joints sit inside the body: widen to the limbs' ends and the head.
    let margin = max(maxX - minX, maxY - minY) * 0.15
    let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let box = CGRect(x: minX - margin, y: minY - margin, width: maxX - minX + 2 * margin, height: maxY - minY + 2 * margin)
      .intersection(bounds)
    guard !box.isNull, box.width >= 16, box.height >= 16, box.width * box.height < old.width * old.height * 0.8 else { return nil }
    return box
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
