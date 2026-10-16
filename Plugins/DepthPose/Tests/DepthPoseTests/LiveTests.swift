import CoreGraphics
import Foundation
import Testing

@testable import DepthPose

/// Probes with the real model and the real Vision; they run only with `DTHUB_LIVE_DEPTH=1`:
///
///     DTHUB_LIVE_DEPTH=1 DP_LIVE_MODEL_DIR=<folder with DepthAnythingV2BaseF16.mlpackage> swift test --filter LiveTests
///
/// Without `DP_LIVE_MODEL_DIR` the model is downloaded from the release (needs the sandbox off and the release
/// published; set `DP_LIVE_DOWNLOAD=1` to say so). With `DP_LIVE_OUT=<folder>` the pictures they make are written there.
@Suite(
  "Live probes", .serialized,
  .enabled(if: ProcessInfo.processInfo.environment["DTHUB_LIVE_DEPTH"] == "1"))
struct LiveTests {
  /// One folder for the model, so the three probes download it once (and a second run, never).
  private var modelFolder: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dthub-depthpose-live-base", isDirectory: true)
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

  /// The model in the live folder: from a package on disk when `DP_LIVE_MODEL_DIR` says where, else downloaded.
  private func readyStore() async throws -> DPModelStore {
    let store = DPModelStore(folder: modelFolder)
    store.cleanUpLeftovers()
    if !store.isPresent() {
      let started = Date()
      if let dir = ProcessInfo.processInfo.environment["DP_LIVE_MODEL_DIR"] {
        try await store.installLocalPackage(from: URL(fileURLWithPath: dir))
      } else {
        try await store.install { _ in }
      }
      print("LIVE install+compile: \(Date().timeIntervalSince(started)) s")
    }
    return store
  }

  @Test func theRealPackageMatchesTheManifestCompilesAndOpens() async throws {
    let store = try await readyStore()
    #expect(store.isPresent())
    #expect(FileManager.default.fileExists(atPath: store.compiledURL.path))
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["DP_LIVE_DOWNLOAD"] == "1"))
  func theReleaseDownloadsAndMatchesTheManifest() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dthub-depthpose-live-download-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = DPModelStore(folder: folder)
    try await store.install { _ in }
    #expect(store.isPresent())
  }

  @Test(arguments: [(640, 480, "landscape"), (480, 640, "portrait"), (512, 512, "square")])
  func theRealModelSeesTheBottomOfAFloorAsNearer(shape: (Int, Int, String)) async throws {
    let store = try await readyStore()
    let estimator = DepthEstimator(model: try CoreMLDepthModel(compiledModel: store.compiledURL))
    let scene = floorScene(width: shape.0, height: shape.1)
    _ = try estimator.depthMap(for: scene)  // the first run compiles for the Neural Engine
    let started = Date()
    let map = try estimator.depthMap(for: scene)
    print("LIVE depth map \(shape.2): \(Int(Date().timeIntervalSince(started) * 1000)) ms for \(scene.width)x\(scene.height)")
    save(scene, as: "live-scene-\(shape.2).png")
    save(map, as: "live-depth-\(shape.2).png")
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

  // MARK: The whole-body pose model

  private var poseFolder: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dthub-depthpose-live-pose", isDirectory: true)
  }

  private func environment(_ name: String) -> String? { ProcessInfo.processInfo.environment[name] }

  /// The pose model in its live folder: from a package on disk when `DP_LIVE_POSE_DIR` says where, else downloaded.
  private func readyPoseStore() async throws -> DPModelStore {
    let store = DPModelStore(
      folder: poseFolder, files: DPModelManifest.dwposeLF16, packageName: DPModelManifest.dwposeLPackageName,
      baseURL: DPModelManifest.dwposeLBaseURL)
    store.cleanUpLeftovers()
    if !store.isPresent() {
      let started = Date()
      if let dir = environment("DP_LIVE_POSE_DIR") {
        try await store.installLocalPackage(from: URL(fileURLWithPath: dir))
      } else {
        try await store.install { _ in }
      }
      print("LIVE pose install+compile: \(Date().timeIntervalSince(started)) s")
    }
    return store
  }

  private func photo() throws -> CGImage? {
    guard let path = environment("DP_LIVE_POSE_PHOTO") else {
      print("LIVE: DP_LIVE_POSE_PHOTO not set, the photo probes are skipped")
      return nil
    }
    guard let image = DPImage.load(file: URL(fileURLWithPath: path)) else {
      Issue.record("the photo at DP_LIVE_POSE_PHOTO cannot be read")
      return nil
    }
    return image
  }

  private func detector(_ store: DPModelStore) throws -> DWPoseDetector {
    DWPoseDetector(network: try CoreMLPoseNetwork(compiledModel: store.compiledURL), boxFinder: VisionPersonBoxFinder())
  }

  @Test func thePosePackageMatchesTheManifestCompilesAndOpens() async throws {
    let store = try await readyPoseStore()
    #expect(store.isPresent())
    #expect(FileManager.default.fileExists(atPath: store.compiledURL.path))
  }

  @Test func visionFindsThePersonBoxesInAPhoto() async throws {
    guard let image = try photo() else { return }
    let boxes = try await VisionPersonBoxFinder().boxes(in: image)
    print("LIVE Vision boxes: \(boxes.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" })")
    #expect(!boxes.isEmpty)
  }

  @Test func thePoseModelFindsAWholeBodyInAPhoto() async throws {
    guard let image = try photo() else { return }
    let detector = try detector(try await readyPoseStore())
    _ = try await detector.figures(in: image)  // the first run prepares the Neural Engine
    let started = Date()
    let figures = try await detector.figures(in: image)
    print("LIVE pose: \(figures.count) figure(s) in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
    #expect(!figures.isEmpty)
    for figure in figures {
      #expect(figure.face.count == 68 && figure.leftHand.count == 21 && figure.rightHand.count == 21)
      let face = figure.face.map(\.confidence).reduce(0, +) / 68
      let body = figure.body.values.map(\.confidence).reduce(0, +) / Double(max(1, figure.body.count))
      print("LIVE figure: body \(body) face \(face)")
      #expect(face > 0.5 && body > 0.4)
    }
    if let image = DPPoseRenderer.render(figures, width: image.width, height: image.height) { save(image, as: "live-pose.png") }
  }

  @Test func aSceneWithoutPeopleGivesNoFigure() async throws {
    let detector = try detector(try await readyPoseStore())
    let figures = try await detector.figures(in: floorScene())
    #expect(figures.isEmpty)
  }

  /// The points of the model agree with ONNX Runtime's (the same boxes, rtmlib's pre-processing), within a few pixels.
  @Test func thePoseModelAgreesWithOnnxRuntime() async throws {
    guard let image = try photo(), let goldenPath = environment("DP_LIVE_POSE_GOLDEN") else {
      print("LIVE: DP_LIVE_POSE_GOLDEN not set, the comparison is skipped")
      return
    }
    struct Golden: Decodable {
      var boxes: [[Double]]
      var keypoints: [[[Double]]]
    }
    let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: URL(fileURLWithPath: goldenPath)))
    let boxes = golden.boxes.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
    let detector = try detector(try await readyPoseStore())
    let figures = try detector.figures(in: image, boxes: boxes)
    // The figures come biggest box first: put the golden people in the same order.
    let order = boxes.indices.sorted { boxes[$0].width * boxes[$0].height > boxes[$1].width * boxes[$1].height }
    #expect(figures.count == order.count)
    let compared: [(DPJoint, Int)] = [
      (.nose, 0), (.leftShoulder, 5), (.rightShoulder, 6), (.leftElbow, 7), (.rightElbow, 8), (.leftWrist, 9),
      (.rightWrist, 10), (.leftHip, 11), (.rightHip, 12),
    ]
    var worst = 0.0, count = 0
    for (figure, index) in zip(figures, order) {
      for (joint, coco) in compared {
        let reference = golden.keypoints[index][coco]
        guard reference[2] > 0.5, let point = figure.body[joint] else { continue }
        let distance = hypot(point.x * Double(image.width) - reference[0], point.y * Double(image.height) - reference[1])
        worst = max(worst, distance)
        count += 1
      }
    }
    print("LIVE agreement with ONNX Runtime: \(count) joints, worst \(worst) px")
    #expect(count > 10 && worst < 6)
  }
}
