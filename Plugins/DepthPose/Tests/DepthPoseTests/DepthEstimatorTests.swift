import CoreGraphics
import Foundation
import Testing

@testable import DepthPose

/// A model that records what it was asked and answers with a horizontal gradient inside the picture it was given, and
/// 255 in the padding the estimator added around it (so a test can see whether the padding was cropped out).
final class FakeDepthModel: DPDepthModel, @unchecked Sendable {
  private let lock = NSLock()
  private var _received: [(Int, Int)] = []
  var received: [(Int, Int)] { lock.withLock { _received } }
  let inputSize: (width: Int, height: Int)
  let outputSize: (Int, Int)?
  let low: UInt8
  let high: UInt8
  /// The content rectangle (in input pixels) outside which the answer is 255; nil = no padding marked.
  var content: DepthEstimator.Fit?
  var failure: (any Error)?

  init(inputSize: (width: Int, height: Int) = (518, 392), outputSize: (Int, Int)? = nil, low: UInt8 = 10, high: UInt8 = 40) {
    self.inputSize = inputSize
    self.outputSize = outputSize
    self.low = low
    self.high = high
  }

  func predict(_ image: CGImage) throws -> CGImage {
    lock.withLock { _received.append((image.width, image.height)) }
    if let failure { throw failure }
    let (w, h) = outputSize ?? (image.width, image.height)
    var bytes = [UInt8](repeating: 255, count: w * h)
    let sx = Double(w) / Double(image.width), sy = Double(h) / Double(image.height)
    let box = content ?? DepthEstimator.Fit(width: image.width, height: image.height, x: 0, y: 0)
    let x0 = Int((Double(box.x) * sx).rounded()), x1 = Int((Double(box.x + box.width) * sx).rounded())
    let y0 = Int((Double(box.y) * sy).rounded()), y1 = Int((Double(box.y + box.height) * sy).rounded())
    for y in y0..<min(h, y1) {
      for x in x0..<min(w, x1) {
        let t = x1 - x0 <= 1 ? 0 : Double(x - x0) / Double(x1 - x0 - 1)
        bytes[y * w + x] = UInt8(Double(low) + Double(high - low) * t)
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
  @Test func aPictureIsFittedInsideTheModelInputKeepingItsProportions() {
    let input = (width: 518, height: 392)
    #expect(DepthEstimator.fit(width: 800, height: 600, into: input) == .init(width: 518, height: 389, x: 0, y: 1))
    #expect(DepthEstimator.fit(width: 768, height: 1024, into: input) == .init(width: 294, height: 392, x: 112, y: 0))
    #expect(DepthEstimator.fit(width: 500, height: 500, into: input) == .init(width: 392, height: 392, x: 63, y: 0))
  }

  @Test func anExtremeShapeStillGetsAtLeastOnePixel() {
    let wide = DepthEstimator.fit(width: 10000, height: 100, into: (width: 518, height: 392))
    #expect(wide.width == 518 && wide.height == 5 && wide.y == 193)
    let tall = DepthEstimator.fit(width: 100, height: 10000, into: (width: 518, height: 392))
    #expect(tall.height == 392 && tall.width == 4)
  }

  @Test func theModelGetsExactlyItsInputSize() throws {
    let model = FakeDepthModel()
    _ = try DepthEstimator(model: model).depthMap(for: Pictures.image(width: 200, height: 100))
    _ = try DepthEstimator(model: model).depthMap(for: Pictures.image(width: 100, height: 300))
    #expect(model.received.count == 2 && model.received.allSatisfy { $0 == (518, 392) })
  }

  @Test func theOutputGoesBackToTheSizeOfTheImage() throws {
    let map = try DepthEstimator(model: FakeDepthModel()).depthMap(for: Pictures.image(width: 200, height: 100))
    #expect(map.width == 200 && map.height == 100)
  }

  @Test func aHugeImageIsReducedBeforeTheModel() throws {
    let map = try DepthEstimator(model: FakeDepthModel()).depthMap(for: Pictures.image(width: 3000, height: 1500))
    #expect(map.width == 2048 && map.height == 1024)
  }

  @Test func thePaddingIsCroppedOutOfTheAnswer() throws {
    // A portrait picture leaves bands at the sides of the model input; the fake paints them 255.
    let model = FakeDepthModel()
    model.content = DepthEstimator.fit(width: 100, height: 200, into: (width: 518, height: 392))
    let map = try DepthEstimator(model: model).depthMap(for: Pictures.image(width: 100, height: 200))
    #expect(map.width == 100 && map.height == 200)
    #expect(Pictures.pixel(map, 0, 100)[0] <= 6)  // the left edge of the content, not the white band
    #expect(Pictures.pixel(map, 99, 100)[0] >= 250)
  }

  @Test func theOutputIsNormalisedFrom0To255() throws {
    let map = try DepthEstimator(model: FakeDepthModel(low: 10, high: 40)).depthMap(
      for: Pictures.image(width: 100, height: 20))
    #expect(Pictures.pixel(map, 0, 10)[0] <= 6)
    #expect(Pictures.pixel(map, 99, 10)[0] >= 250)
  }

  @Test func theHighestModelValueIsTheNearestAndTheBrightest() throws {
    let map = try DepthEstimator(model: FakeDepthModel()).depthMap(for: Pictures.image(width: 100, height: 20))
    #expect(Pictures.pixel(map, 90, 10)[0] > Pictures.pixel(map, 10, 10)[0])
  }

  @Test func invertingFlipsNearAndFar() throws {
    let map = try DepthEstimator(model: FakeDepthModel(), invertsModelOutput: true).depthMap(
      for: Pictures.image(width: 100, height: 20))
    #expect(Pictures.pixel(map, 0, 10)[0] >= 250)
    #expect(Pictures.pixel(map, 99, 10)[0] <= 6)
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
