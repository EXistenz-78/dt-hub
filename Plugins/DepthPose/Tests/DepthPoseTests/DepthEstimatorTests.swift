import CoreGraphics
import Foundation
import Testing

@testable import DepthPose

/// A model that records what it was asked and answers with a horizontal gradient of its own size.
final class FakeDepthModel: DPDepthModel, @unchecked Sendable {
  private let lock = NSLock()
  private var _received: [(Int, Int)] = []
  var received: [(Int, Int)] { lock.withLock { _received } }
  let outputSize: (Int, Int)
  let low: UInt8
  let high: UInt8
  var failure: (any Error)?

  init(outputSize: (Int, Int) = (37, 29), low: UInt8 = 10, high: UInt8 = 40) {
    self.outputSize = outputSize
    self.low = low
    self.high = high
  }

  func predict(_ image: CGImage) throws -> CGImage {
    lock.withLock { _received.append((image.width, image.height)) }
    if let failure { throw failure }
    let (w, h) = outputSize
    var bytes = [UInt8](repeating: 0, count: w * h)
    for y in 0..<h {
      for x in 0..<w {
        bytes[y * w + x] = w == 1 ? low : UInt8(Double(low) + Double(high - low) * Double(x) / Double(w - 1))
      }
    }
    return Pictures.gray(bytes, width: w, height: h)
  }
}

extension Pictures {
  static func gray(_ bytes: [UInt8], width: Int, height: Int) -> CGImage {
    CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: true,
      intent: .defaultIntent)!
  }
}

struct Boom: Error {}

@Suite("DepthEstimator")
struct DepthEstimatorTests {
  @Test func theInputHasShortSide518AndLongSideAMultipleOf14() {
    #expect(DepthEstimator.inputSize(forWidth: 1024, height: 768) == (686, 518))
    #expect(DepthEstimator.inputSize(forWidth: 768, height: 1024) == (518, 686))
    #expect(DepthEstimator.inputSize(forWidth: 500, height: 500) == (518, 518))
    #expect(DepthEstimator.inputSize(forWidth: 200, height: 100) == (1036, 518))
  }

  @Test func anExtremeShapeKeepsTheLongSideInCheck() {
    let size = DepthEstimator.inputSize(forWidth: 10000, height: 100)
    #expect(size.0 == 2072 && size.1 == 518)
  }

  @Test func theModelGetsTheInputSizeAndTheOutputGoesBackToTheImage() throws {
    let model = FakeDepthModel()
    let map = try DepthEstimator(model: model).depthMap(for: Pictures.image(width: 200, height: 100))
    #expect(model.received.count == 1 && model.received[0] == (1036, 518))
    #expect(map.width == 200 && map.height == 100)
  }

  @Test func aHugeImageIsReducedBeforeTheModel() throws {
    let model = FakeDepthModel()
    let map = try DepthEstimator(model: model).depthMap(for: Pictures.image(width: 3000, height: 1500))
    #expect(map.width == 2048 && map.height == 1024)
  }

  @Test func theOutputIsNormalisedFrom0To255() throws {
    let map = try DepthEstimator(model: FakeDepthModel(low: 10, high: 40)).depthMap(
      for: Pictures.image(width: 100, height: 20))
    #expect(Pictures.pixel(map, 0, 10)[0] <= 2)
    #expect(Pictures.pixel(map, 99, 10)[0] >= 253)
  }

  @Test func theHighestModelValueIsTheNearestAndTheBrightest() throws {
    let map = try DepthEstimator(model: FakeDepthModel()).depthMap(for: Pictures.image(width: 100, height: 20))
    #expect(Pictures.pixel(map, 90, 10)[0] > Pictures.pixel(map, 10, 10)[0])
  }

  @Test func invertingFlipsNearAndFar() throws {
    let map = try DepthEstimator(model: FakeDepthModel(), invertsModelOutput: true).depthMap(
      for: Pictures.image(width: 100, height: 20))
    #expect(Pictures.pixel(map, 0, 10)[0] >= 253)
    #expect(Pictures.pixel(map, 99, 10)[0] <= 2)
  }

  @Test func aFlatOutputDoesNotDivideByZero() throws {
    let map = try DepthEstimator(model: FakeDepthModel(low: 77, high: 77)).depthMap(
      for: Pictures.image(width: 40, height: 40))
    let values = Set((0..<40).map { Pictures.pixel(map, $0, 20)[0] })
    #expect(values.count == 1)
  }

  @Test func aFailingModelThrows() {
    let model = FakeDepthModel()
    model.failure = Boom()
    #expect(throws: Boom.self) { try DepthEstimator(model: model).depthMap(for: Pictures.image(width: 40, height: 40)) }
  }
}
