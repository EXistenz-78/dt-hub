import CoreGraphics
import Foundation
import Testing

@testable import DepthPose

/// Probes with the real model and the real Vision. They go to the network (Hugging Face, once) and need the sandbox
/// off, so they run only with `DTHUB_LIVE_DEPTH=1`:
///
///     DTHUB_LIVE_DEPTH=1 swift test --filter LiveTests
///
/// With `DP_LIVE_OUT=<folder>` the pictures they make are written there.
@Suite(
  "Live probes", .serialized,
  .enabled(if: ProcessInfo.processInfo.environment["DTHUB_LIVE_DEPTH"] == "1"))
struct LiveTests {
  /// One folder for the model, so the three probes download it once (and a second run, never).
  private var modelFolder: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dthub-depthpose-live-model", isDirectory: true)
  }

  private func save(_ image: CGImage, as name: String) {
    guard let folder = ProcessInfo.processInfo.environment["DP_LIVE_OUT"], let png = DPPoseRenderer.pngData(image) else { return }
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
  }

  /// A checkerboard floor in perspective under a pale sky: the bottom of the picture is the nearest thing in it.
  private func floorScene(width: Int = 640, height: Int = 480) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let horizon = height / 3
    for y in 0..<height {
      for x in 0..<width {
        let i = (y * width + x) * 4
        if y < horizon {
          (bytes[i], bytes[i + 1], bytes[i + 2]) = (170, 200, 235)
        } else {
          let depth = 1.0 / Double(y - horizon + 1)
          let u = (Double(x) - Double(width) / 2) * depth * 0.5
          let v = depth * 40
          let dark = (Int(floor(u)) + Int(floor(v))) & 1 == 0
          (bytes[i], bytes[i + 1], bytes[i + 2]) = dark ? (60, 60, 65) : (200, 190, 170)
        }
        bytes[i + 3] = 255
      }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
  }

  private func meanGrey(_ image: CGImage, rows: Range<Int>) -> Double {
    var total = 0.0, count = 0.0
    for y in rows {
      for x in stride(from: 0, to: image.width, by: 4) {
        total += Double(Pictures.pixel(image, x, y)[0])
        count += 1
      }
    }
    return total / count
  }

  @Test func theRealModelDownloadsMatchesTheManifestAndOpens() async throws {
    let store = DPModelStore(folder: modelFolder)
    store.cleanUpLeftovers()
    if !store.isPresent() {
      let started = Date()
      try await store.install { _ in }
      print("LIVE download+compile: \(Date().timeIntervalSince(started)) s")
    }
    #expect(store.isPresent())
    #expect(FileManager.default.fileExists(atPath: store.compiledURL.path))
  }

  @Test func theRealModelSeesTheBottomOfAFloorAsNearer() async throws {
    let store = DPModelStore(folder: modelFolder)
    if !store.isPresent() { try await store.install { _ in } }
    let estimator = DepthEstimator(model: try CoreMLDepthModel(compiledModel: store.compiledURL))
    let scene = floorScene()
    _ = try estimator.depthMap(for: scene)  // the first run compiles for the Neural Engine
    let started = Date()
    let map = try estimator.depthMap(for: scene)
    print("LIVE depth map: \(Int(Date().timeIntervalSince(started) * 1000)) ms for \(scene.width)x\(scene.height)")
    save(scene, as: "live-scene.png")
    save(map, as: "live-depth.png")
    #expect(map.width == scene.width && map.height == scene.height)
    let near = meanGrey(map, rows: (scene.height - 40)..<scene.height)
    let far = meanGrey(map, rows: (scene.height / 3 + 5)..<(scene.height / 3 + 45))
    print("LIVE mean grey near \(near) far \(far)")
    // Near must be brighter. If this fails the model gives far as bright: set `invertsModelOutput` where the plug-in
    // builds the estimator, and flip this test.
    #expect(near > far)
  }

  @Test func visionAnswersOnAStickFigureWithoutAnError() async throws {
    let size = 512
    let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setStrokeColor(CGColor(gray: 0, alpha: 1))
    context.setLineWidth(8)
    context.strokeEllipse(in: CGRect(x: 226, y: 380, width: 60, height: 60))
    for (a, b) in [((256, 380), (256, 220)), ((256, 340), (190, 280)), ((256, 340), (322, 280)), ((256, 220), (210, 100)), ((256, 220), (302, 100))] {
      context.move(to: CGPoint(x: a.0, y: a.1))
      context.addLine(to: CGPoint(x: b.0, y: b.1))
    }
    context.strokePath()
    let people = try await VisionPoseDetector().people(in: context.makeImage()!)
    print("LIVE Vision on a stick figure: \(people.count) person(s)")
    #expect(people.count >= 0)  // the answer can be empty: the point is that it comes without an error
  }
}
