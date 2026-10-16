import CoreGraphics
import Foundation
import Testing

@testable import DepthPose

/// A network whose every keypoint has its peak at the centre bin (288, 384) with the value `value`: every point lands on
/// the centre of the box it was asked for.
final class FakeNetwork: DPPoseNetwork, @unchecked Sendable {
  var value: Float
  var failure: (any Error)?
  private let lock = NSLock()
  private var _sizes: [(Int, Int)] = []
  var sizes: [(Int, Int)] { lock.withLock { _sizes } }
  init(value: Float) { self.value = value }

  func simcc(for crop: CGImage) throws -> (x: [Float], y: [Float]) {
    lock.withLock { _sizes.append((crop.width, crop.height)) }
    if let failure { throw failure }
    var x = [Float](repeating: 0, count: 133 * 576)
    var y = [Float](repeating: 0, count: 133 * 768)
    for keypoint in 0..<133 {
      x[keypoint * 576 + 288] = value
      y[keypoint * 768 + 384] = value
    }
    return (x, y)
  }
}

struct FakeBoxFinder: DPPersonBoxFinding {
  var found: [CGRect]
  func boxes(in image: CGImage) async throws -> [CGRect] { found }
}

struct Broken: Error {}

@Suite("DWPoseDetector")
struct DWPoseDetectorTests {
  private let image = Pictures.image(width: 400, height: 300)

  private func detector(value: Float = 0.9, boxes: [CGRect] = []) -> (DWPoseDetector, FakeNetwork) {
    let network = FakeNetwork(value: value)
    return (DWPoseDetector(network: network, boxFinder: FakeBoxFinder(found: boxes)), network)
  }

  private func nose(_ figure: DPFigure) -> (Double, Double) { (figure.body[.nose]?.x ?? -1, figure.body[.nose]?.y ?? -1) }

  @Test func oneFigurePerBoxTheBiggestFirst() async throws {
    let small = CGRect(x: 20, y: 20, width: 40, height: 80)
    let big = CGRect(x: 200, y: 50, width: 120, height: 220)
    let (detector, network) = detector(boxes: [small, big])
    let figures = try await detector.figures(in: image)
    #expect(figures.count == 2)
    #expect(abs(nose(figures[0]).0 - 260.0 / 400) < 1e-6 && abs(nose(figures[0]).1 - 160.0 / 300) < 1e-6)
    #expect(abs(nose(figures[1]).0 - 40.0 / 400) < 1e-6 && abs(nose(figures[1]).1 - 60.0 / 300) < 1e-6)
    #expect(network.sizes.allSatisfy { $0 == (288, 384) })
  }

  @Test func noBoxesMeansTheWholePicture() async throws {
    let (detector, network) = detector(boxes: [])
    let figures = try await detector.figures(in: image)
    #expect(figures.count == 1 && network.sizes.count == 1)
    #expect(abs(nose(figures[0]).0 - 0.5) < 1e-6 && abs(nose(figures[0]).1 - 0.5) < 1e-6)
  }

  @Test func aFigureBelowTheBodyScoreIsDropped() async throws {
    let box = CGRect(x: 100, y: 50, width: 60, height: 150)
    let (weak, _) = detector(value: 0.2, boxes: [box])
    #expect(try await weak.figures(in: image).isEmpty)
    let (strong, _) = detector(value: 0.9, boxes: [box])
    #expect(try await strong.figures(in: image).count == 1)
    let (edge, _) = detector(value: 0.35, boxes: [box])
    #expect(try await edge.figures(in: image).count == 1, "the threshold itself passes")
  }

  @Test func aPictureWithNoPersonGivesNothing() async throws {
    let (detector, network) = detector(value: 0.1, boxes: [])
    #expect(try await detector.figures(in: image).isEmpty)
    #expect(network.sizes.count == 1, "the whole picture was tried once")
  }

  @Test func atMostTwelvePeopleAndTheBiggestOnes() async throws {
    let boxes = (0..<30).map { (index: Int) -> CGRect in
      CGRect(x: Double(index * 12), y: 10, width: Double(20 + index), height: Double(40 + 2 * index))
    }
    let (detector, _) = detector(boxes: boxes)
    let figures = try await detector.figures(in: image)
    #expect(figures.count == 12)
    // The 12 biggest are boxes 29...18, biggest first; every nose is the centre of its box.
    let expected = (18...29).reversed().map { (index: Int) -> Double in
      (Double(index * 12) + Double(20 + index) / 2) / 400
    }
    for (figure, x) in zip(figures, expected) { #expect(abs(nose(figure).0 - x) < 1e-6) }
  }

  @Test func theBoxesGivenAreUsedAsTheyAre() throws {
    let (detector, _) = detector()
    let figures = try detector.figures(in: image, boxes: [CGRect(x: 100, y: 50, width: 60, height: 150)])
    #expect(figures.count == 1)
    #expect(abs(nose(figures[0]).0 - 130.0 / 400) < 1e-6 && abs(nose(figures[0]).1 - 125.0 / 300) < 1e-6)
  }

  @Test func aBoxThatLeavesThePictureStillWorks() throws {
    let (detector, _) = detector()
    let figures = try detector.figures(in: image, boxes: [CGRect(x: 350, y: 250, width: 200, height: 200)])
    #expect(figures.count == 1)
  }

  @Test func anErrorOfTheNetworkIsThrown() async {
    let (detector, network) = detector(boxes: [CGRect(x: 0, y: 0, width: 50, height: 50)])
    network.failure = Broken()
    await #expect(throws: Broken.self) { _ = try await detector.figures(in: image) }
  }

  @Test func theFaceAndTheHandsComeWithTheFigure() async throws {
    let (detector, _) = detector(boxes: [CGRect(x: 100, y: 50, width: 60, height: 150)])
    let figure = try await detector.figures(in: image)[0]
    #expect(figure.face.count == 68 && figure.leftHand.count == 21 && figure.rightHand.count == 21)
  }
}
