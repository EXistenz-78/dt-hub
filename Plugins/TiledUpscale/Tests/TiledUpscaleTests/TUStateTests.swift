import CoreGraphics
import Foundation
import Testing

@testable import TiledUpscale

@MainActor
struct TUStateTests {
  let folder = TestImages.temporaryFolder()

  private func state(family: String? = "flux2_9b") -> TUState {
    let state = TUState(store: TUStore(folder: nil), italian: false)
    state.family = family
    state.tempFolder = folder.path
    return state
  }

  private func photo(_ width: Int, _ height: Int) -> CGImage { TestImages.solid(width, height, (1, 2, 3)) }

  @Test func summaryShowsTheFinalSizeTilesAndPasses() {
    let summary = TUSummary.make(sourceWidth: 1000, sourceHeight: 1000, factor: 2, overlap: .standard)
    #expect(summary.width == 1984 && summary.height == 1984)
    #expect(summary.columns == 3 && summary.rows == 3 && summary.passes == 9)
    #expect(summary.cropped)
    #expect(summary.verdict == .ok)
    let exact = TUSummary.make(sourceWidth: 512, sourceHeight: 512, factor: 2, overlap: .standard)
    #expect(exact.width == 1024 && exact.passes == 1 && !exact.cropped)
  }

  @Test func theSummaryFollowsTheChoices() {
    let s = state()
    s.setImage(photo(1000, 1000), name: "a")
    #expect(s.summary?.passes == 9)
    s.overlap = .wide
    #expect(s.summary?.passes == 9)
    s.factor = 4
    #expect(s.summary?.width == 3968)
    #expect(s.summary?.passes == TileGrid.plan(width: 3968, height: 3968, overlap: .wide, tile: s.tileSize).count)
  }

  @Test func prepareIsOffWithoutAnImageOrWithAnUnsupportedModel() {
    let s = state()
    #expect(!s.canPrepare)
    s.setImage(photo(512, 512), name: "a")
    #expect(s.canPrepare)
    let qwen = state(family: "qwen_image_2.1")
    qwen.setImage(photo(512, 512), name: "a")
    #expect(!qwen.canPrepare)
    #expect(qwen.status == TUState.text(.unsupportedModel, italian: false))
  }

  @Test func prepareRefusesAboveTheLimits() async {
    let s = state()
    s.setImage(photo(4300, 4300), name: "big")
    s.factor = 4
    #expect(s.summary?.verdict == .refuse)
    #expect(!s.canPrepare)
    var contributed = 0
    await s.prepare(confirmed: true, contribute: { _ in contributed += 1; return nil }, registerPreset: { _ in nil })
    #expect(contributed == 0)
  }

  @Test func aBigJobNeedsConfirmation() async {
    let s = state()
    s.setImage(photo(3000, 3000), name: "big")
    s.factor = 4
    #expect(s.summary?.verdict == .warn)
    #expect(s.needsConfirmation)
    var contributed = 0
    await s.prepare(confirmed: false, contribute: { _ in contributed += 1; return nil }, registerPreset: { _ in nil })
    #expect(contributed == 0)
  }

  @Test func theFirstPressOnABigJobOnlyAsksAndTheChoicesClearTheQuestion() async {
    let s = state()
    s.setImage(photo(3000, 3000), name: "big")
    s.factor = 4
    #expect(!s.awaitingConfirmation, "nothing asked yet: the first press is not a confirmation")
    await s.prepare(confirmed: s.awaitingConfirmation, contribute: { _ in ["type": "ok"] }, registerPreset: { _ in nil })
    #expect(s.awaitingConfirmation && !s.isPrepared)
    var contributed = 0
    await s.prepare(confirmed: s.awaitingConfirmation, contribute: { _ in contributed += 1; return ["type": "ok"] }, registerPreset: { _ in nil })
    #expect(contributed == 1 && s.isPrepared && !s.awaitingConfirmation)
    s.factor = 2
    #expect(!s.awaitingConfirmation)
  }

  @Test func prepareSendsAGuidedPipeline() async throws {
    let s = state()
    s.setImage(photo(1000, 1000), name: "a")
    var sent: [String: Any] = [:]
    var registered: [String: Any] = [:]
    await s.prepare(
      confirmed: true, contribute: { sent = $0; return ["type": "ok"] }, registerPreset: { registered = $0; return ["type": "ok"] })
    let pipeline = try #require(sent["pipeline"] as? [String: Any])
    #expect(pipeline["guided"] as? Bool == true)
    #expect(pipeline["passes"] as? Int == 9)
    let estimate = try #require(pipeline["estimate"] as? [String: Any])
    let size = try #require(estimate["size"] as? [String: Int])
    #expect(size["width"] == 1024 && size["height"] == 1024)
    #expect(estimate["preset"] as? String == "TUP · FLUX.2 klein 9B")
    #expect(registered["name"] as? String == "TUP · FLUX.2 klein 9B")
    #expect(s.isPrepared)
  }

  @Test func theTriggerWordOfTheServerIsNotUsedForFlux() throws {
    let s = state()
    s.loraTriggers = ["f2_ultra_real_v5_pro_lora_f16.ckpt": "ULTRA"]
    s.setImage(photo(512, 512), name: "a")
    let session = try #require(s.makeSession())
    let answer = try #require(
      JSONSerialization.jsonObject(with: session.next(TUNextRequest(index: 1, count: 1, previous: nil))) as? [String: Any])
    #expect((answer["fields"] as? [String: Any])?["prompt"] as? String == TUPresetTable.fluxPrompt, "the trigger of the server is not used")
  }

  @Test func theChoicesAreKeptPerProject() {
    let one = folder.appendingPathComponent("one")
    let two = folder.appendingPathComponent("two")
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.switchProject(folder: one)
    s.factor = 4
    s.overlap = .wide
    s.loraWeight = 0.7
    s.switchProject(folder: two)
    #expect(s.factor == 2 && s.overlap == .standard && s.loraWeight == 1)
    s.switchProject(folder: one)
    #expect(s.factor == 4 && s.overlap == .wide && s.loraWeight == 0.7)
  }

  @Test func finishingSendsTheComposedPictureAsAResult() async throws {
    let s = state()
    s.setImage(photo(512, 512), name: "a")
    var sent: [String: Any] = [:]
    s.contribute = { sent = $0; return ["type": "ok"] }
    await s.prepare(confirmed: true, contribute: { _ in ["type": "ok"] }, registerPreset: { _ in nil })
    _ = await s.sessionNext(Data(#"{"type":"session.next","index":1,"count":1}"#.utf8))
    let previous = TestImages.write(TestImages.solid(1024, 1024, (9, 9, 9)), in: folder, name: "p.png")
    let done = await s.sessionNext(
      Data(#"{"type":"session.next","index":2,"count":1,"previous":{"path":"\#(previous.path)","width":1024,"height":1024}}"#.utf8))
    #expect(String(decoding: done, as: UTF8.self).contains("done"))
    await s.sessionEnded(reason: "finished")
    let result = try #require(sent["result"] as? [String: Any])
    let path = try #require(result["path"] as? String)
    #expect(TUImage.load(URL(fileURLWithPath: path))?.width == 1024, "the composed picture, in the plug-in's folder")
    #expect(path.hasPrefix(folder.path))
    #expect(result["description"] as? String == "Tiled Upscale 2× · 1×1 tiles · LoRA 1.00 · tile 1024 · free 192 · blur 30 · margin 29 · fade 64 · tone 100%/16")
    #expect(result["name"] as? String == "Tiled Upscale")
    #expect(s.resultReady && !s.isPrepared)
    #expect(s.status == TUState.text(.addedToResults, italian: false))
  }

  @Test func aResultTheAppRefusesIsReported() async throws {
    let s = state()
    s.setImage(photo(512, 512), name: "a")
    s.contribute = { _ in ["type": "ok", "problems": ["Tiled Upscale: unreadable"]] }
    await s.prepare(confirmed: true, contribute: { _ in ["type": "ok"] }, registerPreset: { _ in nil })
    _ = await s.sessionNext(Data(#"{"type":"session.next","index":1,"count":1}"#.utf8))
    let previous = TestImages.write(TestImages.solid(1024, 1024, (9, 9, 9)), in: folder, name: "p.png")
    _ = await s.sessionNext(
      Data(#"{"type":"session.next","index":2,"count":1,"previous":{"path":"\#(previous.path)","width":1024,"height":1024}}"#.utf8))
    await s.sessionEnded(reason: "finished")
    #expect(!s.resultReady)
    #expect(s.status.contains("unreadable"))
  }

  @Test func thePreviewBaseFollowsThePictureAndTheChoices() throws {
    let s = state()
    #expect(s.previewBase == nil && s.plan == nil)
    s.setImage(photo(1000, 1000), name: "a")
    let base = try #require(s.previewBase)
    #expect(base.width == base.height, "1984 × 1984 is square")
    #expect(s.plan?.count == s.summary?.passes)
    s.setImage(photo(1000, 500), name: "b")
    let wide = try #require(s.previewBase)
    #expect(wide.width > wide.height)
    s.factor = 4
    #expect(s.plan?.width == s.summary?.width)
  }

  @Test func theProgressGrowsWithTheTilesAndResetsWithTheChoices() async throws {
    let s = state()
    s.setImage(photo(1000, 1000), name: "a")
    await s.prepare(confirmed: true, contribute: { _ in ["type": "ok"] }, registerPreset: { _ in nil })
    #expect(s.tilesDone == 0 && s.previewProgress == nil)
    _ = await s.sessionNext(Data(#"{"type":"session.next","index":1,"count":9}"#.utf8))
    let tile = TestImages.write(TestImages.solid(1024, 1024, (9, 9, 9)), in: folder, name: "t.png")
    _ = await s.sessionNext(
      Data(#"{"type":"session.next","index":2,"count":9,"previous":{"path":"\#(tile.path)","width":1024,"height":1024}}"#.utf8))
    #expect(s.tilesDone == 1)
    #expect(s.previewProgress != nil)
    s.overlap = .wide
    #expect(s.tilesDone == 0 && s.previewProgress == nil)
  }

  @Test func changingTheLoRAStrengthKeepsThePreview() throws {
    let s = state()
    s.setImage(photo(1000, 1000), name: "a")
    let base = try #require(s.previewBase)
    s.loraWeight = 0.6
    #expect(s.previewBase === base, "the strength does not change the picture: nothing is drawn again")
    s.factor = 4
    #expect(s.previewBase !== base)
  }

  @Test func theLoRAStrengthRangeIsTheGenerationCardsAndASavedValueIsBroughtIntoIt() throws {
    #expect(TUPresetTable.loraWeightRange == -4...4)
    let one = folder.appendingPathComponent("range")
    try FileManager.default.createDirectory(at: one, withIntermediateDirectories: true)
    for (saved, expected) in [(9.0, 4.0), (-9.0, -4.0), (-4.0, -4.0), (4.0, 4.0), (0.3, 0.3)] {
      try Data(#"{"factor":2,"overlap":256,"loraWeight":\#(saved)}"#.utf8).write(to: one.appendingPathComponent("state.json"))
      #expect(TUStore(folder: one).load().loraWeight == expected, "saved \(saved)")
    }
  }

  @Test func theEstimateIsTheSizeOfTheBiggestTile() async throws {
    let s = state()
    s.setImage(photo(1200, 1200), name: "big")
    s.factor = 4
    s.tileSize = 1536
    var sent: [String: Any] = [:]
    await s.prepare(confirmed: true, contribute: { sent = $0; return ["type": "ok"] }, registerPreset: { _ in nil })
    let pipeline = try #require(sent["pipeline"] as? [String: Any])
    let size = try #require((pipeline["estimate"] as? [String: Any])?["size"] as? [String: Int])
    #expect(size["width"] == 1536 && size["height"] == 1536)
    #expect(pipeline["passes"] as? Int == s.summary?.passes)
  }

  @Test func theSummarySaysHowManyPixelsTheModelWillMake() {
    // 3968 × 3968: with 1024 tiles the sides are 4 × 1024 + 896 = 4992 long in total (overlaps count twice), 25 tiles.
    let small = TUSummary.make(sourceWidth: 1000, sourceHeight: 1000, factor: 4, overlap: .standard, tile: 1024)
    #expect(small.passes == 25)
    #expect(abs(small.generatedMegapixels - 4992.0 * 4992.0 / 1_000_000) < 0.001)
    // 3968 with a 1536 tile: sides of 1536 + 1536 + 1408; with a 2048 one: 2048 + 2048 + 384. Both come to 4480, 9 tiles.
    let mid = TUSummary.make(sourceWidth: 1000, sourceHeight: 1000, factor: 4, overlap: .standard, tile: 1536)
    let big = TUSummary.make(sourceWidth: 1000, sourceHeight: 1000, factor: 4, overlap: .standard, tile: 2048)
    #expect(mid.passes == 9 && big.passes == 9)
    #expect(abs(mid.generatedMegapixels - 4480.0 * 4480.0 / 1_000_000) < 0.001)
    #expect(abs(big.generatedMegapixels - mid.generatedMegapixels) < 0.001, "the same pixels in all, in bigger tiles")
    #expect(mid.generatedMegapixels < small.generatedMegapixels)
  }

  @Test func qwenIsSupportedAndTheFileTellsTurboFromTheOther() {
    let s = state(family: "qwen_image_2.1")
    s.model = "qwen_image_2.1_turbo_i8x.ckpt"
    s.setImage(photo(512, 512), name: "a")
    #expect(s.canPrepare && s.preset?.name == "TUP · Qwen Image 2.1 Turbo")
    s.model = "qwen_image_2.1_i8x.ckpt"
    #expect(s.preset?.name == "TUP · Qwen Image 2.1")
    s.model = nil
    #expect(!s.canPrepare, "a Qwen model with no file name has no preset")
  }

  @Test func theLoRAStrengthIsRememberedPerPreset() {
    let s = state(family: "flux2_9b")
    #expect(s.loraWeight == 1)
    s.loraWeight = 0.6
    s.family = "qwen_image_2.1"
    s.model = "qwen_image_2.1_turbo_i8x.ckpt"
    #expect(s.loraWeight == 2.5, "each preset starts from its own")
    s.loraWeight = 1.5
    s.model = "qwen_image_2.1_i8x.ckpt"
    #expect(s.loraWeight == 2.5)
    s.model = "qwen_image_2.1_turbo_i8x.ckpt"
    #expect(s.loraWeight == 1.5)
    s.family = "flux2_9b"
    s.model = nil
    #expect(s.loraWeight == 0.6)
  }

  @Test func theLoRAStrengthsAreKeptPerProject() {
    let one = folder.appendingPathComponent("w1")
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.family = "qwen_image_2.1"
    s.model = "qwen_image_2.1_turbo_i8x.ckpt"
    s.switchProject(folder: one)
    s.loraWeight = 2.0
    s.switchProject(folder: folder.appendingPathComponent("w2"))
    #expect(s.loraWeight == 2.5)
    s.switchProject(folder: one)
    #expect(s.loraWeight == 2.0)
  }

  @Test func anOldProjectKeepsItsFluxStrength() throws {
    let old = folder.appendingPathComponent("old")
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    try Data(#"{"factor":2,"overlap":256,"loraWeight":0.8}"#.utf8).write(to: old.appendingPathComponent("state.json"))
    let s = state(family: "flux2_9b")
    s.switchProject(folder: old)
    #expect(s.loraWeight == 0.8)
    s.family = "qwen_image_2.1"
    s.model = "qwen_image_2.1_i8x.ckpt"
    #expect(s.loraWeight == 2.5)
  }

  @Test func theQwenPassCarriesItsPromptAndItsLoRA() async throws {
    let s = state(family: "qwen_image_2.1")
    s.model = "qwen_image_2.1_turbo_i8x.ckpt"
    s.setImage(photo(512, 512), name: "a")
    s.loraTriggers = ["q21_detail_fix_2.0_lora_f16.ckpt": "SHOULD NOT APPEAR"]
    var sent: [String: Any] = [:]
    await s.prepare(confirmed: true, contribute: { sent = $0; return ["type": "ok"] }, registerPreset: { _ in nil })
    let estimate = try #require((sent["pipeline"] as? [String: Any])?["estimate"] as? [String: Any])
    let fields = try #require(estimate["fields"] as? [String: Any])
    let prompt = try #require(fields["prompt"] as? String)
    #expect(prompt.hasPrefix("Upscale this image") && !prompt.contains("SHOULD NOT APPEAR"))
    let lora = try #require((estimate["loras"] as? [[String: Any]])?.first)
    #expect(lora["file"] as? String == "q21_detail_fix_2.0_lora_f16.ckpt" && lora["weight"] as? Double == 2.5)
    #expect(estimate["preset"] as? String == "TUP · Qwen Image 2.1 Turbo")
  }
}
