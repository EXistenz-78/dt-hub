import CoreGraphics
import Foundation
import Testing

@testable import TiledUpscale

/// A whole enlargement with a "model" that returns every tile unchanged: the composed picture must be the enlarged
/// picture, to the byte (no tile shifted, no seam, nothing lost at the edges).
struct TUSessionIdentityTests {
  private func bytes(_ image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(
      data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
      space: TestImages.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setBlendMode(.copy)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return data
  }

  /// A picture where every pixel is different enough to show a shift.
  private func gradient(_ width: Int, _ height: Int) -> CGImage {
    var data = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let base = (y * width + x) * 4
        data[base] = UInt8((x * 7 + y) % 256)
        data[base + 1] = UInt8((y * 5 + x / 3) % 256)
        data[base + 2] = UInt8((x + y * 11) % 256)
      }
    }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: TestImages.space,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(data) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  }

  private func compose(width: Int, height: Int, factor: Int, overlap: TileOverlap) throws -> (composed: CGImage, expected: CGImage, passes: Int) {
    let folder = TestImages.temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = gradient(width, height)
    let scaled = TileGrid.scaledSize(width: width, height: height, factor: factor)
    let expected = try #require(TUCanvas(scaling: source, factor: factor, size: scaled)?.image())
    let preset = try #require(TUPresetTable.preset(forFamily: "flux2_9b"))
    let session = TUSession(
      source: source, factor: factor, overlap: overlap, loraWeight: 1, trigger: "", preset: preset, tempFolder: folder)
    var previous: TUNextRequest.Previous?
    var index = 1
    var passes = 0
    while true {
      let data = session.next(TUNextRequest(index: index, count: session.plan.count, previous: previous))
      let answer = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
      if answer["done"] as? Bool == true { break }
      passes += 1
      let start = try #require((answer["startImage"] as? [String: Any])?["path"] as? String)
      let size = try #require(answer["size"] as? [String: Int])
      let result = folder.appendingPathComponent("result-\(index).png")
      try FileManager.default.copyItem(at: URL(fileURLWithPath: start), to: result)
      previous = TUNextRequest.Previous(path: result.path, width: try #require(size["width"]), height: try #require(size["height"]))
      index += 1
    }
    let composed = try #require(session.end("finished"))
    return (composed, expected, passes)
  }

  @Test func identityResultsComposeTheEnlargedPicture() throws {
    for overlap in TileOverlap.allCases {
      let run = try compose(width: 1300, height: 700, factor: 2, overlap: overlap)
      #expect(run.composed.width == 2560 && run.composed.height == 1344)
      #expect(run.passes == TileGrid.plan(width: 2560, height: 1344, overlap: overlap).count)
      #expect(bytes(run.composed) == bytes(run.expected), "overlap \(overlap.rawValue)")
    }
  }

  @Test func aPictureThatFitsOneTileComposesToo() throws {
    let run = try compose(width: 400, height: 300, factor: 2, overlap: .standard)
    #expect(run.passes == 1)
    #expect(bytes(run.composed) == bytes(run.expected))
  }
}
