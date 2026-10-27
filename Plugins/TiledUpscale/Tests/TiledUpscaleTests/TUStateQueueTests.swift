import CoreGraphics
import Foundation
import Testing

@testable import TiledUpscale

@MainActor
struct TUStateQueueTests {
  let folder = TestImages.temporaryFolder()

  private func state(family: String? = "flux2_9b") -> TUState {
    let state = TUState(store: TUStore(folder: nil), italian: false)
    state.family = family
    state.tempFolder = folder.path
    return state
  }

  private let accept: ([String: Any]) async -> [String: Any]? = { _ in ["type": "ok"] }

  private func prepared(_ width: Int = 1000, _ height: Int = 1000, name: String = "foto.png") async -> TUState {
    let s = state()
    s.setImage(TestImages.solid(width, height, (1, 2, 3)), name: name)
    await s.prepare(confirmed: true, contribute: accept, registerPreset: accept)
    return s
  }

  private func restore(
    _ s: TUState, _ captured: [String: Any], at queueFolder: URL, model: String? = "flux.ckpt", family: String? = "flux2_9b",
    contribute: @escaping ([String: Any]) async -> [String: Any]? = { _ in ["type": "ok"] }
  ) async -> String? {
    await s.queuePrepare(
      folder: queueFolder, state: captured, model: model, family: family, contribute: contribute, registerPreset: accept)
  }

  @Test func captureNeedsAPreparedPipeline() async {
    let s = state()
    s.setImage(TestImages.solid(512, 512, (1, 2, 3)), name: "a")
    #expect(s.queueCapture(folder: folder.appendingPathComponent("q")) == nil, "a picture that is not prepared is not captured")
    await s.prepare(confirmed: true, contribute: accept, registerPreset: accept)
    #expect(s.queueCapture(folder: folder.appendingPathComponent("q")) != nil)
  }

  @Test func captureWritesTheSourcePictureAndTheChoices() async throws {
    let s = state()
    s.setImage(TestImages.solid(1000, 1000, (1, 2, 3)), name: "foto.png")
    s.factor = 4
    s.extraPrompt = "più luce"
    await s.prepare(confirmed: true, contribute: accept, registerPreset: accept)
    let queueFolder = folder.appendingPathComponent("q")
    let captured = try #require(s.queueCapture(folder: queueFolder))
    #expect(captured["image"] as? String == "source.png")
    #expect(captured["imageName"] as? String == "foto.png")
    let loaded = try #require(TUImage.load(queueFolder.appendingPathComponent("source.png")))
    #expect(loaded.width == 1000 && loaded.height == 1000)
    let choice = try JSONDecoder().decode(TUChoice.self, from: JSONSerialization.data(withJSONObject: try #require(captured["choice"])))
    #expect(choice.factor == 4)
    #expect(choice.extraPrompt == "più luce")
  }

  @Test func prepareRestoresTheChoicesAndThePicture() async throws {
    let s1 = state()
    s1.setImage(TestImages.solid(1000, 1000, (1, 2, 3)), name: "foto.png")
    s1.factor = 4
    s1.overlap = .wide
    s1.maskBlur = 12
    s1.extraPrompt = "più luce"
    await s1.prepare(confirmed: true, contribute: accept, registerPreset: accept)
    let queueFolder = folder.appendingPathComponent("q")
    let captured = try #require(s1.queueCapture(folder: queueFolder))

    let s2 = state()
    let problem = await restore(s2, captured, at: queueFolder)
    #expect(problem == nil)
    #expect(s2.factor == s1.factor && s2.overlap == s1.overlap)
    #expect(s2.settings == s1.settings)
    #expect(s2.loraWeights == s1.loraWeights)
    #expect(s2.extraPrompt == s1.extraPrompt)
    #expect(s2.imageName == "foto.png")
    #expect(s2.summary?.passes == s1.summary?.passes)
    #expect(s2.plan?.count == s1.plan?.count)
    #expect(s2.isPrepared)
  }

  @Test func prepareNeverAsksForConfirmation() async throws {
    // 3000 px × 4 is 144 megapixels: above the warning, below the refusal.
    let s1 = state()
    s1.setImage(TestImages.solid(3000, 3000, (1, 2, 3)), name: "big.png")
    s1.factor = 4
    #expect(s1.needsConfirmation)
    await s1.prepare(confirmed: true, contribute: accept, registerPreset: accept)
    let queueFolder = folder.appendingPathComponent("q")
    let captured = try #require(s1.queueCapture(folder: queueFolder))

    let s2 = state()
    let problem = await restore(s2, captured, at: queueFolder)
    #expect(problem == nil)
    #expect(s2.needsConfirmation, "the job is still a big one")
    #expect(!s2.awaitingConfirmation)
    #expect(s2.isPrepared)
  }

  @Test func prepareUsesTheModelAndFamilyOfTheMessage() async throws {
    let s1 = await prepared()
    let queueFolder = folder.appendingPathComponent("q")
    let captured = try #require(s1.queueCapture(folder: queueFolder))

    let s2 = state(family: "qwen_image_2.1")  // a model this plug-in does not support: the context it holds is out of date
    #expect(s2.preset == nil)
    let problem = await restore(s2, captured, at: queueFolder, model: "flux_2.ckpt", family: "flux2_9b")
    #expect(problem == nil)
    #expect(s2.family == "flux2_9b")
    #expect(s2.model == "flux_2.ckpt")
    #expect(s2.isPrepared)
  }

  @Test func prepareFailsWhenThePictureFileIsGone() async throws {
    let s1 = await prepared()
    let queueFolder = folder.appendingPathComponent("q")
    let captured = try #require(s1.queueCapture(folder: queueFolder))
    try FileManager.default.removeItem(at: queueFolder.appendingPathComponent("source.png"))

    let s2 = state()
    let problem = await restore(s2, captured, at: queueFolder)
    #expect(problem != nil)
    #expect(!s2.isPrepared)
  }

  @Test func prepareFailsWhenTheAppDoesNotAnswer() async throws {
    let s1 = await prepared()
    let queueFolder = folder.appendingPathComponent("q")
    let captured = try #require(s1.queueCapture(folder: queueFolder))

    let s2 = state()
    let problem = await restore(s2, captured, at: queueFolder, contribute: { _ in nil })
    #expect(problem != nil)
    #expect(!s2.isPrepared)
  }
}
