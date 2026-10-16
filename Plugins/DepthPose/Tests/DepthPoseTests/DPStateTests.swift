import CoreGraphics
import Foundation
import Testing

@testable import DepthPose

/// Answers with the people it is given; can wait at a gate to let the test change things meanwhile.
final class FakeDetector: DPPoseDetecting, @unchecked Sendable {
  var people: [DPPerson]
  var gate: AsyncGate?
  private let lock = NSLock()
  private var _calls = 0
  var calls: Int { lock.withLock { _calls } }
  init(people: [DPPerson] = []) { self.people = people }

  func people(in image: CGImage) async throws -> [DPPerson] {
    lock.withLock { _calls += 1 }
    if let gate { await gate.wait() }
    return people
  }
}

let standingPerson: DPPerson = [
  .nose: DPPoint(x: 0.5, y: 0.2, confidence: 1), .neck: DPPoint(x: 0.5, y: 0.5, confidence: 1),
  .rightShoulder: DPPoint(x: 0.25, y: 0.5, confidence: 1),
]

@MainActor
@Suite("DPState")
struct DPStateTests {
  struct Rig {
    let state: DPState
    let detector: FakeDetector
    let downloader: FakeDownloader
    let models: DPModelStore
    let temp: URL
    let spy: ContributionSpy
  }

  @MainActor final class ContributionSpy {
    var contributions: [[String: Any]] = []
    var answer: [String: Any]? = ["type": "ok", "conflicts": 0]
  }

  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dpst-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// A state with fakes for Vision, the model and the network. `modelReady` installs the fake model first.
  private func rig(modelReady: Bool, people: [DPPerson] = [standingPerson], opens: Bool = true) async throws -> Rig {
    let root = try folder()
    let downloader = FakeDownloader()
    downloader.contents = ["Manifest.json": Data("{}".utf8)]
    let opensNow = LockedValue(true)
    let models = DPModelStore(
      folder: root.appendingPathComponent("model"),
      files: [DPModelFile(path: "M.mlpackage/Manifest.json", size: 2, sha256: nil)], packageName: "M.mlpackage",
      downloader: downloader,
      compile: { package in
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("c-\(UUID().uuidString).mlmodelc")
        try FileManager.default.copyItem(at: package, to: out)
        try Data("ok".utf8).write(to: out.appendingPathComponent("marker"))
        return out
      },
      validate: { opensNow.value && FileManager.default.fileExists(atPath: $0.appendingPathComponent("marker").path) })
    if modelReady { try await models.install { _ in } }
    opensNow.set(opens)  // a model that was fine when installed and does not open any more
    let detector = FakeDetector(people: people)
    let defaults = UserDefaults(suiteName: "dp-state-\(UUID().uuidString)")!
    let state = DPState(
      store: DPStore(defaults: defaults), models: models, detector: detector,
      makeDepth: { _ in DepthEstimator(model: FakeDepthModel()) }, italian: false)
    state.tempFolder = root.appendingPathComponent("temp").path
    state.active = true
    await state.refreshModelState()
    return Rig(state: state, detector: detector, downloader: downloader, models: models, temp: root, spy: ContributionSpy())
  }

  private func picture() -> Data { Pictures.data(Pictures.image(width: 80, height: 60)) }

  @Test func createWithBothMakesBothMaps() async throws {
    let r = try await rig(modelReady: true)
    r.state.select(depth: true, pose: true)
    r.state.setImage(data: picture(), name: "a.png")
    await r.state.create()
    #expect(r.state.depthImage?.width == 80 && r.state.poseImage?.width == 80)
    #expect(r.state.status == L.text(.created, italian: false))
    #expect(!r.state.isWorking)
  }

  @Test func createWithDepthOnlyDoesNotRunVision() async throws {
    let r = try await rig(modelReady: true)
    r.state.select(depth: true, pose: false)
    r.state.setImage(data: picture(), name: "a.png")
    await r.state.create()
    #expect(r.state.depthImage != nil && r.state.poseImage == nil)
    #expect(r.detector.calls == 0)
  }

  @Test func createWithPoseOnlyWorksWithoutTheModel() async throws {
    let r = try await rig(modelReady: false)
    r.state.select(depth: false, pose: true)
    r.state.setImage(data: picture(), name: "a.png")
    await r.state.create()
    #expect(r.state.poseImage != nil && r.state.depthImage == nil)
  }

  @Test func bothWithoutTheModelMakesOnlyThePoseAndSaysSo() async throws {
    let r = try await rig(modelReady: false)
    r.state.select(depth: true, pose: true)
    r.state.setImage(data: picture(), name: "a.png")
    await r.state.create()
    #expect(r.state.poseImage != nil && r.state.depthImage == nil)
    #expect(r.state.status == L.text(.poseOnlyBecauseNoModel, italian: false))
  }

  @Test func depthOnlyWithoutTheModelAsksToDownload() async throws {
    let r = try await rig(modelReady: false)
    r.state.select(depth: true, pose: false)
    r.state.setImage(data: picture(), name: "a.png")
    #expect(!r.state.canCreate)
    await r.state.create()
    #expect(r.state.depthImage == nil)
    #expect(r.state.status == L.text(.depthMissing, italian: false))
  }

  @Test func noPersonSaysSoAndKeepsTheDepth() async throws {
    let r = try await rig(modelReady: true, people: [])
    r.state.select(depth: true, pose: true)
    r.state.setImage(data: picture(), name: "a.png")
    await r.state.create()
    #expect(r.state.depthImage != nil && r.state.poseImage == nil)
    #expect(r.state.status == L.text(.noPerson, italian: false))
  }

  @Test func anUnreadableImageSaysSoAndKeepsTheOldOne() async throws {
    let r = try await rig(modelReady: true)
    r.state.setImage(data: picture(), name: "a.png")
    r.state.setImage(data: Data("garbage".utf8), name: "b.png")
    #expect(r.state.status == L.text(.unreadableImage, italian: false))
    #expect(r.state.imageName == "a.png" && r.state.image != nil)
  }

  @Test func replacingTheImageClearsTheMaps() async throws {
    let r = try await rig(modelReady: true)
    r.state.setImage(data: picture(), name: "a.png")
    await r.state.create()
    #expect(r.state.depthImage != nil)
    r.state.setImage(data: picture(), name: "b.png")
    #expect(r.state.depthImage == nil && r.state.poseImage == nil && r.state.imageName == "b.png")
  }

  @Test func aResultThatArrivesAfterANewImageIsDiscarded() async throws {
    let r = try await rig(modelReady: true)
    let gate = AsyncGate()
    r.detector.gate = gate
    r.state.select(depth: false, pose: true)
    r.state.setImage(data: picture(), name: "a.png")
    let work = Task { await r.state.create() }
    while r.detector.calls == 0 { try await Task.sleep(for: .milliseconds(5)) }
    r.state.setImage(data: picture(), name: "b.png")
    await gate.release()
    await work.value
    #expect(r.state.poseImage == nil && r.state.depthImage == nil)
    #expect(!r.state.isWorking)
  }

  @Test func sendWritesThePNGsAndContributesOnlyTheChosenMaps() async throws {
    let r = try await rig(modelReady: true)
    r.state.select(depth: true, pose: true)
    r.state.setImage(data: picture(), name: "a.png")
    await r.state.create()
    r.state.select(depth: false, pose: true)  // the maps exist, only the pose is wanted
    await r.state.send { [spy = r.spy] in spy.contributions.append($0); return spy.answer }
    let sent = try #require(r.spy.contributions.first?["moodboard"] as? [[String: Any]])
    #expect(sent.map { $0["name"] as? String } == ["Pose"])
    let path = try #require(sent.first?["path"] as? String)
    #expect(path == r.state.tempFolder! + "/" + DPMessages.poseFile)
    #expect(FileManager.default.fileExists(atPath: path))
    #expect(r.state.status == L.text(.sent, italian: false))
  }

  @Test func sendWithBothSendsDepthThenPose() async throws {
    let r = try await rig(modelReady: true)
    r.state.select(depth: true, pose: true)
    r.state.setImage(data: picture(), name: "a.png")
    await r.state.create()
    await r.state.send { [spy = r.spy] in spy.contributions.append($0); return spy.answer }
    let sent = try #require(r.spy.contributions.first?["moodboard"] as? [[String: Any]])
    #expect(sent.map { $0["name"] as? String } == ["Depth", "Pose"])
  }

  @Test func sendWithoutATempFolderSaysSoAndSendsNothing() async throws {
    let r = try await rig(modelReady: true)
    r.state.setImage(data: picture(), name: "a.png")
    await r.state.create()
    r.state.tempFolder = nil
    await r.state.send { [spy = r.spy] in spy.contributions.append($0); return spy.answer }
    #expect(r.spy.contributions.isEmpty)
    #expect(r.state.status == L.text(.noFolder, italian: false))
  }

  @Test func sendReportsConflictsProblemsErrorsAndSilence() async throws {
    let r = try await rig(modelReady: true)
    r.state.setImage(data: picture(), name: "a.png")
    await r.state.create()
    func send(_ answer: [String: Any]?) async -> String {
      await r.state.send { _ in answer }
      return r.state.status
    }
    #expect(await send(["type": "ok", "conflicts": 2]) == L.format(.sentWithConflicts, 2, italian: false))
    #expect(await send(["type": "ok", "problems": ["p"]]).contains("p"))
    #expect(await send(["type": "error", "text": "x"]) == "x")
    #expect(await send(nil) == L.text(.notAnswered, italian: false))
  }

  @Test func sendIsDisabledUntilThereIsSomethingToSendAndThePluginIsOn() async throws {
    let r = try await rig(modelReady: true)
    #expect(!r.state.canSend)
    r.state.setImage(data: picture(), name: "a.png")
    #expect(!r.state.canSend)
    await r.state.create()
    #expect(r.state.canSend)
    r.state.active = false
    #expect(!r.state.canSend)
    r.state.active = true
    r.state.select(depth: true, pose: false)
    r.state.setImage(data: picture(), name: "b.png")
    #expect(!r.state.canSend)
  }

  @Test func theDownloadFollowsTheStoreFromMissingToReady() async throws {
    let r = try await rig(modelReady: false)
    #expect(r.state.modelState == .missing && r.state.showsDownloadButton && !r.state.depthAvailable)
    let gate = AsyncGate()
    r.downloader.gate = gate
    let work = Task { await r.state.downloadModel() }
    while r.downloader.calls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    if case .downloading = r.state.modelState {} else { Issue.record("not downloading: \(r.state.modelState)") }
    await gate.release()
    await work.value
    #expect(r.state.modelState == .ready && !r.state.showsDownloadButton && r.state.depthAvailable)
  }

  @Test func aFailedDownloadGoesBackToMissingWithTheReason() async throws {
    let r = try await rig(modelReady: false)
    r.downloader.failOn = "Manifest.json"
    await r.state.downloadModel()
    #expect(r.state.modelState == .missing)
    #expect(r.state.status.contains("boom"))
  }

  @Test func cancellingTheDownloadGoesBackToMissing() async throws {
    let r = try await rig(modelReady: false)
    let gate = AsyncGate()
    r.downloader.gate = gate
    let work = Task { await r.state.downloadModel() }
    while r.downloader.calls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    r.state.cancelDownload()
    await gate.release()
    await work.value
    #expect(r.state.modelState == .missing)
  }

  @Test func aModelThatDoesNotOpenIsDamaged() async throws {
    let r = try await rig(modelReady: true, opens: false)
    #expect(r.state.modelState == .damaged && r.state.showsDownloadButton && !r.state.depthAvailable)
  }

  @Test func changingProjectKeepsOnlyTheMode() async throws {
    let r = try await rig(modelReady: true)
    let project = r.temp.appendingPathComponent("project")
    r.state.switchProject(folder: project, adoptLegacy: false)
    r.state.select(depth: false, pose: true)
    r.state.setImage(data: picture(), name: "a.png")
    await r.state.create()
    r.state.switchProject(folder: project, adoptLegacy: false)
    #expect(!r.state.wantsDepth && r.state.wantsPose)
    #expect(r.state.image == nil && r.state.poseImage == nil && r.state.imageName.isEmpty)
  }

  @Test func theFirstProjectAdoptsTheModeOfBeforeProjects() async throws {
    let r = try await rig(modelReady: true)
    r.state.select(depth: true, pose: false)  // saved in the defaults: there is no project yet
    r.state.switchProject(folder: r.temp.appendingPathComponent("first"), adoptLegacy: true)
    #expect(r.state.wantsDepth && !r.state.wantsPose)
  }

  @Test func theContextSetsTheTempFolder() async throws {
    let r = try await rig(modelReady: true)
    r.state.apply(context: Data(#"{"type":"context","tempFolder":"/tmp/xyz"}"#.utf8))
    #expect(r.state.tempFolder == "/tmp/xyz")
  }

  @Test func withNoMapChosenThereIsNothingToCreate() async throws {
    let r = try await rig(modelReady: true)
    r.state.setImage(data: picture(), name: "a.png")
    #expect(r.state.canCreate)
    r.state.select(depth: false, pose: false)
    #expect(!r.state.canCreate)
    r.state.select(depth: false, pose: true)
    #expect(r.state.canCreate)
  }

  @Test func theTwoChoicesAreIndependent() async throws {
    let r = try await rig(modelReady: true)
    r.state.wantsDepth = false
    #expect(!r.state.wantsDepth && r.state.wantsPose)
    r.state.wantsPose = false
    r.state.wantsDepth = true
    #expect(r.state.wantsDepth && !r.state.wantsPose)
  }

  @Test func createIsDisabledWithoutAnImage() async throws {
    let r = try await rig(modelReady: true)
    #expect(!r.state.canCreate)
    r.state.setImage(data: picture(), name: "a.png")
    #expect(r.state.canCreate)
  }
}
