import CoreGraphics
import DTHubPluginKit
import Foundation
import Testing

@testable import TiledUpscale

@MainActor
struct TUToolsTests {
  let folder = TestImages.temporaryFolder()
  let state: TUState
  let sent = Sent()

  /// What the plug-in sent to the app.
  @MainActor
  final class Sent {
    var contributions: [[String: Any]] = []
    var presets: [[String: Any]] = []
    var answer: [String: Any]? = ["type": "ok"]
  }

  init() {
    state = TUState(store: TUStore(folder: nil), italian: false)
  }

  func start(family: String? = "flux2_9b", active: Bool = true) {
    state.active = active
    state.family = family
    state.model = "model.ckpt"
    state.tempFolder = folder.path
  }

  func picture(_ width: Int, _ height: Int, name: String = "photo.png") -> String {
    TestImages.write(TestImages.solid(width, height, (10, 20, 30)), in: folder, name: name).path
  }

  struct Answer {
    var text: String
    var isError: Bool
    var startsRun: Bool
    var type: String?
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:] }
  }

  func call(_ tool: String, _ arguments: [String: Any] = [:]) async -> Answer {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let sent = self.sent
    let connection = TUTools.Connection(
      contribute: { message in
        sent.contributions.append(message)
        return sent.answer
      },
      registerPreset: { message in
        sent.presets.append(message)
        return ["type": "ok"]
      })
    let answer = await TUTools.handle(call, state: state, connection: connection)
    let object = try! JSONSerialization.jsonObject(with: answer) as! [String: Any]
    return Answer(
      text: object["text"] as? String ?? "", isError: object["isError"] as? Bool ?? false,
      startsRun: object["startsRun"] as? Bool ?? false, type: object["type"] as? String)
  }

  var passes: Int? { (sent.contributions.last?["pipeline"] as? [String: Any])?["passes"] as? Int }

  // MARK: Declarations

  @Test func theDeclarationsAreWellFormedAndInTheManifest() throws {
    for tool in TUTools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20)
      #expect(tool.families == TUTools.families)
    }
    #expect(TUTools.declarations.map(\.name) == ["get_status", "get_options", "prepare_upscale", "upscale"])
    #expect(TUTools.declarations.map(\.level) == [.read, .read, .edit, .generate])
    #expect(TUTools.families == ["flux2_9b", "flux3_5b", "qwen_image_2.1"])
    let upscale = try #require(TUTools.declarations.last)
    #expect(upscale.parameters.first { $0.name == "image" }?.format == "image")
    #expect(upscale.parameters.first { $0.name == "confirm_large" }?.type == "boolean")
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(TUTools.declarations)) is [[String: Any]])
    #expect(TiledUpscalePlugin().manifest.tools?.count == 4)
    #expect(TiledUpscalePlugin().manifest.version == "1.5")
  }

  @Test func everyFamilyOfTheToolsHasAPreset() {
    for family in TUTools.families {
      #expect(TUPresetTable.preset(forFamily: family, model: "x.ckpt") != nil, Comment(rawValue: family))
    }
  }

  // MARK: Reading

  @Test func nothingWorksBeforeTheContextOrWhenNotActive() async {
    #expect(await call("get_status").isError)
    start(active: false)
    #expect(await call("get_status").text.contains("not active"))
    state.active = true
    state.tempFolder = nil
    #expect(await call("get_status").text.contains("context"))
  }

  @Test func statusSaysWhatTheJobWillBe() async throws {
    start()
    let empty = await call("get_status")
    #expect(!empty.isError && empty.json["hasPicture"] as? Bool == false && empty.json["job"] == nil)
    state.setImage(TestImages.solid(1000, 1000, (1, 2, 3)), name: "foto.png")
    let status = await call("get_status").json
    let job = try #require(status["job"] as? [String: Any])
    let summary = try #require(state.summary)
    #expect(job["tiles"] as? Int == summary.passes)
    #expect(job["finalWidth"] as? Int == summary.width && summary.width == 1984 && job["finalHeight"] as? Int == summary.height)
    #expect(job["preset"] as? String == TUPresetTable.fluxKlein9BName)
    #expect(status["prepared"] as? Bool == false)
    #expect((status["picture"] as? [String: Any])?["name"] as? String == "foto.png")
  }

  @Test func optionsListTheRangesTheDefaultsAndThePresets() async throws {
    start()
    let options = await call("get_options").json
    #expect(options["factors"] as? [Int] == [2, 4])
    #expect(options["overlaps"] as? [Int] == [256, 320])
    let advanced = try #require(options["advanced"] as? [[String: Any]])
    #expect(advanced.map { $0["argument"] as? String } == ["free", "blur", "outset", "fade", "tone_strength", "tone_radius"])
    let presets = try #require(options["presets"] as? [[String: Any]])
    #expect(Set(presets.compactMap { $0["family"] as? String }) == Set(TUTools.families))
    #expect(presets.contains { $0["name"] as? String == "TUP · Qwen Image 2.1 Turbo" })
    #expect((options["limits"] as? [String: Any])?["confirmLargeOverTiles"] as? Int == 100)
  }

  // MARK: Preparing and running

  @Test func prepareProposesThePipelineWithoutAskingToRun() async throws {
    start()
    let path = picture(1000, 1000)
    let answer = await call("prepare_upscale", ["image": path])
    #expect(!answer.isError && !answer.startsRun, Comment(rawValue: answer.text))
    #expect(state.isPrepared && state.imageName == "photo.png")
    let summary = try #require(state.summary)
    #expect(passes == summary.passes)
    #expect((answer.json["job"] as? [String: Any])?["tiles"] as? Int == summary.passes)
    #expect(sent.presets.count == 1)
  }

  @Test func upscalePreparesAndAsksTheAppToRun() async throws {
    start()
    let answer = await call("upscale", ["image": picture(1000, 1000), "factor": 4])
    #expect(!answer.isError && answer.startsRun, Comment(rawValue: answer.text))
    #expect(state.factor == 4 && state.isPrepared)
    let summary = try #require(state.summary)
    #expect(summary.width == 3968 && passes == summary.passes && summary.passes > 1)
  }

  @Test func upscaleWithoutArgumentsRunsWhatWasPrepared() async {
    start()
    _ = await call("prepare_upscale", ["image": picture(1000, 1000)])
    let before = sent.contributions.count
    let answer = await call("upscale")
    #expect(!answer.isError && answer.startsRun)
    #expect(sent.contributions.count == before, "nothing is proposed twice")
  }

  @Test func upscaleWithoutAPictureOrPreparationFails() async {
    start()
    let answer = await call("upscale")
    #expect(answer.isError && !answer.startsRun && answer.text.contains("No picture"))
    #expect(sent.contributions.isEmpty)
  }

  @Test func theChoicesAreAppliedInTheRightOrder() async {
    start()
    let answer = await call(
      "prepare_upscale",
      [
        "image": picture(1500, 1000), "factor": 4, "overlap": 320, "tile_size": 1280, "lora_weight": 0.5, "extra_prompt": "keep the grain",
        "blur": 10, "tone_strength": 40,
      ])
    #expect(!answer.isError, Comment(rawValue: answer.text))
    #expect(state.factor == 4 && state.overlap == .wide)
    #expect(state.tileSize == 1280 && state.loraWeight == 0.5 && state.extraPrompt == "keep the grain")
    #expect(state.maskBlur == 10 && state.toneStrength == 40)
    #expect(state.maskFree == TUSettings.defaultFree(for: .wide), "the new overlap sets the free part")
  }

  @Test func resetAdvancedPutsTheDefaultsBack() async {
    start()
    state.setImage(TestImages.solid(1000, 1000, (1, 2, 3)), name: "a")
    state.maskBlur = 3
    state.toneStrength = 7
    let answer = await call("prepare_upscale", ["reset_advanced": true, "tone_radius": 100])
    #expect(!answer.isError, Comment(rawValue: answer.text))
    #expect(state.maskBlur == TUSettings.defaults(for: .standard).blur && state.toneStrength == TUSettings.defaults(for: .standard).toneStrength)
    #expect(state.toneRadius == 100)
  }

  @Test func aValueOutOfRangeChangesNothing() async {
    start()
    state.setImage(TestImages.solid(1000, 1000, (1, 2, 3)), name: "a")
    for bad: [String: Any] in [
      ["factor": 3], ["factor": 8], ["overlap": 300], ["tile_size": 1000], ["tile_size": 4096], ["lora_weight": 9], ["blur": 99],
      ["free": 300], ["fade": 200], ["tone_radius": 5], ["outset": -1], ["extra_prompt": String(repeating: "x", count: 1001)],
    ] {
      let answer = await call("upscale", bad)
      #expect(answer.isError && !answer.startsRun, Comment(rawValue: "\(bad)"))
    }
    #expect(state.factor == TUChoice.standard.factor && !state.isPrepared && sent.contributions.isEmpty)
  }

  @Test func theFadeIsCheckedAgainstTheOverlapTheJobWillHave() async {
    start()
    state.setImage(TestImages.solid(1000, 1000, (1, 2, 3)), name: "a")
    // At 256 the default free part leaves 64 px to the fade; with free 100 it leaves 156.
    #expect(await call("prepare_upscale", ["fade": 100]).isError)
    #expect(await !call("prepare_upscale", ["free": 100, "fade": 100]).isError)
  }

  @Test func aBigJobNeedsConfirmLargeAndAHugeOneIsRefused() async {
    start()
    let big = picture(3200, 2400, name: "big.png")  // 4× → 12800×9600, 122 megapixels
    let refused = await call("upscale", ["image": big, "factor": 4])
    #expect(refused.isError && !refused.startsRun && refused.text.contains("confirm_large"), Comment(rawValue: refused.text))
    #expect(sent.contributions.isEmpty && !state.isPrepared)
    let allowed = await call("upscale", ["factor": 4, "confirm_large": true])
    #expect(!allowed.isError && allowed.startsRun, Comment(rawValue: allowed.text))
    #expect(state.isPrepared)

    let wide = picture(4200, 1000, name: "wide.png")  // 4× → 16800 px, over the limit
    let huge = await call("upscale", ["image": wide, "factor": 4, "confirm_large": true])
    #expect(huge.isError && huge.text.contains("Too big"), Comment(rawValue: huge.text))
  }

  @Test func aSmallJobDoesNotNeedConfirmLarge() async {
    start()
    let answer = await call("upscale", ["image": picture(1000, 1000), "confirm_large": false])
    #expect(!answer.isError && answer.startsRun)
  }

  @Test func anUnreadablePictureFails() async {
    start()
    let path = folder.appendingPathComponent("broken.png")
    try? Data("not a picture".utf8).write(to: path)
    let answer = await call("upscale", ["image": path.path])
    #expect(answer.isError && answer.text.contains("could not be read") && sent.contributions.isEmpty)
  }

  @Test func aModelWithoutAPresetFails() async {
    start(family: "sdxl")
    let answer = await call("upscale", ["image": picture(1000, 1000)])
    #expect(answer.isError && answer.text.contains("preset") && !answer.startsRun)
  }

  @Test func ifTheAppDoesNotTakeThePipelineTheToolFails() async {
    start()
    sent.answer = nil
    let answer = await call("upscale", ["image": picture(1000, 1000)])
    #expect(answer.isError && !answer.startsRun)
    #expect(!state.isPrepared)
  }

  @Test func theToolCallIsAnsweredThroughThePluginMessage() async throws {
    let plugin = TiledUpscalePlugin()
    let body = try JSONSerialization.data(withJSONObject: ["type": "tool.call", "tool": "get_options", "arguments": [String: Any]()])
    // No host yet (the app starts the plug-in first): unsupported, never a crash.
    let answer = try #require(await plugin.handle(body))
    #expect(String(decoding: answer, as: UTF8.self).contains("unsupported"))
  }
}
