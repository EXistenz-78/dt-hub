import CoreGraphics
import Foundation
import Testing

@testable import DepthPose

/// Returns one figure with a face (20 dots at y = 0.9) and two hands; can fail or wait at a gate.
final class FakeFullDetector: DPFullPoseDetecting, @unchecked Sendable {
  var failure: (any Error)?
  var gate: AsyncGate?
  private let lock = NSLock()
  private var _calls = 0
  var calls: Int { lock.withLock { _calls } }

  func figures(in image: CGImage) async throws -> [DPFigure] {
    lock.withLock { _calls += 1 }
    if let gate { await gate.wait() }
    if let failure { throw failure }
    let face = (0..<20).map { (index: Int) -> DPPoint in DPPoint(x: 0.3 + 0.02 * Double(index), y: 0.9, confidence: 1) }
    return [DPFigure(body: standingPerson, face: face)]
  }
}

@MainActor
@Suite("DPState, the pose model and the two downloads")
struct DPStateFullPoseTests {
  struct Rig {
    let state: DPState
    let vision: FakeDetector
    let full: FakeFullDetector
    let depthDownloader: FakeDownloader
    let poseDownloader: FakeDownloader
    let depthStore: DPModelStore
    let poseStore: DPModelStore
    let root: URL
  }

  private func store(_ root: URL, package: String, downloader: FakeDownloader) -> DPModelStore {
    DPModelStore(
      folder: root.appendingPathComponent("models"),
      files: [DPModelFile(path: "\(package)/Manifest.json", size: 2, sha256: nil)], packageName: package,
      downloader: downloader,
      compile: { source in
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("c-\(UUID().uuidString).mlmodelc")
        try FileManager.default.copyItem(at: source, to: out)
        try Data("ok".utf8).write(to: out.appendingPathComponent("marker"))
        return out
      },
      validate: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("marker").path) })
  }

  private func rig(depthReady: Bool = false, poseReady: Bool = false, withPoseStore: Bool = true) async throws -> Rig {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dpfp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let depthDownloader = FakeDownloader(), poseDownloader = FakeDownloader()
    for downloader in [depthDownloader, poseDownloader] { downloader.contents = ["Manifest.json": Data("{}".utf8)] }
    let depthStore = store(root, package: "M.mlpackage", downloader: depthDownloader)
    let poseStore = store(root, package: "P.mlpackage", downloader: poseDownloader)
    if depthReady { try await depthStore.install { _ in } }
    if poseReady { try await poseStore.install { _ in } }
    let vision = FakeDetector(people: [standingPerson])
    let full = FakeFullDetector()
    let makeFull: (@Sendable (URL) throws -> any DPFullPoseDetecting)? = withPoseStore ? { @Sendable _ in full } : nil
    let state = DPState(
      store: DPStore(defaults: UserDefaults(suiteName: "dp-fp-\(UUID().uuidString)")!), models: depthStore,
      detector: vision, makeDepth: { _ in DepthEstimator(model: FakeDepthModel()) },
      poseModels: withPoseStore ? poseStore : nil, makeFullPose: makeFull, italian: false)
    state.tempFolder = root.appendingPathComponent("temp").path
    state.active = true
    await state.refreshModelState()
    return Rig(
      state: state, vision: vision, full: full, depthDownloader: depthDownloader, poseDownloader: poseDownloader,
      depthStore: depthStore, poseStore: poseStore, root: root)
  }

  private func picture() -> Data { Pictures.data(Pictures.image(width: 80, height: 60)) }

  private func isWhite(_ pixel: [Int]) -> Bool { pixel.allSatisfy { $0 > 200 } }

  private func createPose(_ r: Rig) async {
    r.state.select(depth: false, pose: true)
    r.state.setImage(data: picture(), name: "a.png")
    await r.state.create()
  }

  @Test func theFullPoseIsUsedWhenItsModelIsReady() async throws {
    let r = try await rig(poseReady: true)
    #expect(r.state.poseModelState == .ready)
    await createPose(r)
    #expect(r.full.calls == 1 && r.vision.calls == 0)
    let image = try #require(r.state.poseImage)
    #expect(isWhite(Pictures.pixel(image, 24, 54)), "a dot of the face")
    #expect(r.state.status == L.text(.created, italian: false))
  }

  @Test func visionIsTheFallbackWithoutTheModel() async throws {
    let r = try await rig()
    #expect(r.state.poseModelState == .missing)
    await createPose(r)
    #expect(r.full.calls == 0 && r.vision.calls == 1)
    let image = try #require(r.state.poseImage)
    #expect(!isWhite(Pictures.pixel(image, 24, 54)), "no face from Vision")
    #expect(r.state.status == L.text(.created, italian: false))
  }

  @Test func aFailingFullDetectorFallsBackToVisionWithANote() async throws {
    let r = try await rig(poseReady: true)
    r.full.failure = Broken()
    await createPose(r)
    #expect(r.full.calls == 1 && r.vision.calls == 1)
    #expect(r.state.poseImage != nil)
    #expect(r.state.poseModelState == .damaged && r.state.showsPoseDownloadButton)
    #expect(r.state.status.contains(L.text(.poseModelDamaged, italian: false)))
  }

  @Test func withoutAPoseStoreThePoseIsVisionAndThereIsNoButton() async throws {
    let r = try await rig(withPoseStore: false)
    await createPose(r)
    #expect(r.vision.calls == 1 && r.full.calls == 0)
    #expect(!r.state.showsPoseDownloadButton)
    await r.state.downloadModel(.pose)  // nothing to download: no effect
    #expect(r.state.poseModelState == .missing)
  }

  @Test func theTwoDownloadsAreIndependent() async throws {
    let r = try await rig()
    let depthGate = AsyncGate(), poseGate = AsyncGate()
    r.depthDownloader.gate = depthGate
    r.poseDownloader.gate = poseGate
    let depthTask = Task { await r.state.downloadModel(.depth) }
    let poseTask = Task { await r.state.downloadModel(.pose) }
    while r.depthDownloader.calls.isEmpty || r.poseDownloader.calls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    if case .downloading = r.state.modelState {} else { Issue.record("depth: \(r.state.modelState)") }
    if case .downloading = r.state.poseModelState {} else { Issue.record("pose: \(r.state.poseModelState)") }
    await depthGate.release()
    await depthTask.value
    #expect(r.state.modelState == .ready)
    if case .downloading = r.state.poseModelState {} else { Issue.record("pose should still be downloading") }
    await poseGate.release()
    await poseTask.value
    #expect(r.state.poseModelState == .ready && !r.state.showsPoseDownloadButton)
  }

  @Test func cancellingOneLeavesTheOtherUntouched() async throws {
    let r = try await rig()
    let depthGate = AsyncGate(), poseGate = AsyncGate()
    r.depthDownloader.gate = depthGate
    r.poseDownloader.gate = poseGate
    let depthTask = Task { await r.state.downloadModel(.depth) }
    let poseTask = Task { await r.state.downloadModel(.pose) }
    while r.depthDownloader.calls.isEmpty || r.poseDownloader.calls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    r.state.cancelDownload(.pose)
    await depthGate.release()
    await poseGate.release()
    await depthTask.value
    await poseTask.value
    #expect(r.state.modelState == .ready)
    #expect(r.state.poseModelState == .missing)
    #expect(!FileManager.default.fileExists(atPath: r.poseStore.packageURL.path))
  }

  @Test func aPoseDownloadFailureShowsTheReasonAndStaysMissing() async throws {
    let r = try await rig(depthReady: true)
    r.poseDownloader.failOn = "Manifest.json"
    await r.state.downloadModel(.pose)
    #expect(r.state.poseModelState == .missing)
    #expect(r.state.status.contains("boom"))
    #expect(r.state.modelState == .ready, "the depth model is not touched")
  }

  @Test func aPoseModelPackageFoundInTheFolderIsCompiledAtLaunch() async throws {
    let r = try await rig()
    try FileManager.default.createDirectory(at: r.poseStore.packageURL, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: r.poseStore.packageURL.appendingPathComponent("Manifest.json"))
    await r.state.prepare()
    #expect(r.state.poseModelState == .ready)
    #expect(r.state.modelState == .missing)
  }

  @Test func prepareLooksAtBothModels() async throws {
    let r = try await rig(depthReady: true, poseReady: true)
    await r.state.prepare()
    #expect(r.state.modelState == .ready && r.state.poseModelState == .ready)
  }

  @Test func thePoseButtonShowsOnlyWhenTheModelIsMissingOrDamagedAndThereIsAStore() async throws {
    let r = try await rig()
    #expect(r.state.showsPoseDownloadButton)
    let ready = try await rig(poseReady: true)
    #expect(!ready.state.showsPoseDownloadButton)
    let none = try await rig(withPoseStore: false)
    #expect(!none.state.showsPoseDownloadButton)
  }
}
