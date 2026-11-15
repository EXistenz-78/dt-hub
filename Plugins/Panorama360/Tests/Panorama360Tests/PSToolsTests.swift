import CoreGraphics
import DTHubPluginKit
import Foundation
import Testing

@testable import Panorama360

@MainActor
@Suite("Panorama 360 tools")
struct PSToolsTests {
  @MainActor
  final class Spy {
    var bodies: [[String: Any]] = []
    var answer: [String: Any]? = ["type": "ok"]
    var presetCalls = 0
    var llm: [DTHubLLMAnswer] = []
    var asked: [String] = []
  }

  let spy = Spy()
  let state: PSState
  let project = TestImages.tempFolder()

  init() {
    state = PSState(italian: false)
    state.switchProject(folder: project)
    state.presetsFolder = TestImages.tempFolder()
    state.active = true
    apply(result: nil)
  }

  func apply(result: URL?) {
    let last = result.map { #","lastResult":{"path":"\#($0.path)","name":"\#($0.lastPathComponent)"}"# } ?? ""
    state.apply(
      context: Data(
        #"{"type":"context","model":"flux_2_klein_base_9b_i8x.ckpt","tempFolder":"\#(TestImages.tempFolder().path)"\#(last)}"#.utf8))
  }

  func picture(_ name: String = "p.png", _ w: Int = 60, _ h: Int = 40) -> String {
    TestImages.file(TestImages.solid(w, h, 200, 50, 50), in: TestImages.tempFolder(), name: name, type: "public.png").path
  }

  struct Answer {
    var text: String
    var isError: Bool
    var startsRun: Bool
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:] }
    var stickers: [[String: Any]] { json["stickers"] as? [[String: Any]] ?? [] }
  }

  func call(_ tool: String, _ arguments: [String: Any] = [:]) async -> Answer {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let spy = self.spy
    let connection = PSTools.Connection(
      contribute: { spy.bodies.append($0); return spy.answer },
      registerPresets: { spy.presetCalls += 1 },
      ask: { prompt, _, _ in
        spy.asked.append(prompt)
        return spy.llm.isEmpty ? .failure("No answer.") : spy.llm.removeFirst()
      })
    let data = await PSTools.handle(call, state: state, connection: connection)
    let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    return Answer(
      text: object["text"] as? String ?? "", isError: object["isError"] as? Bool ?? false,
      startsRun: object["startsRun"] as? Bool ?? false)
  }

  // MARK: Declarations

  @Test func theDeclarationsAreWellFormedAndInTheManifest() throws {
    for tool in PSTools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20)
    }
    #expect(
      PSTools.declarations.map(\.name) == [
        "get_status", "add_sticker", "set_sticker", "remove_sticker", "clear_stickers", "set_description", "improve_description", "undo_improve",
        "send_panorama", "fix_seam",
      ])
    // Only the seam correction generates by itself (it is a pipeline the app holds); the canvas is sent and the app's run makes it.
    #expect(PSTools.declarations.map(\.level) == [.read] + Array(repeating: .edit, count: 8) + [.generate])
    let add = try #require(PSTools.declarations.first { $0.name == "add_sticker" })
    #expect(add.parameters.first { $0.name == "image" }?.format == "image" && add.parameters.first { $0.name == "image" }?.required == true)
    #expect(try #require(PSTools.declarations.first { $0.name == "improve_description" }).timeout == 600)
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(PSTools.declarations)) is [[String: Any]])
    let plugin = Panorama360Plugin(dataFolder: TestImages.tempFolder())
    #expect(plugin.manifest.tools?.count == 10 && plugin.manifest.version == "1.5")
    #expect(plugin.manifest.families == ["flux2_9b", "flux2_4b"])
  }

  // MARK: Reading

  @Test func theStatusShowsTheCanvasTheModeAndWhySeamIsOff() async {
    let answer = await call("get_status")
    #expect(!answer.isError && !answer.startsRun)
    let json = answer.json
    #expect(json["stickers"] as? [Any] != nil && json["mode"] as? String == "normal" && json["preset"] as? String == "PAN · 360 ERP")
    #expect(json["modelIsBase"] as? Bool == true && json["canSend"] as? Bool == false && json["canFixSeam"] as? Bool == false)
    #expect(json["seamProblem"] as? String != nil && (json["canvas"] as? [String: Int]) == ["width": 2048, "height": 1024])
    #expect((json["note"] as? String)?.contains("data") == true)
  }

  @Test func anAgentReadsEnglishWhateverTheSystemLanguageIsAndTheTabKeepsIts() async {
    let italian = PSState(italian: true)
    italian.switchProject(folder: TestImages.tempFolder())
    italian.active = true
    let call = DTHubToolCall(Data(#"{"type":"tool.call","tool":"get_status","arguments":{}}"#.utf8))!
    let data = await PSTools.handle(
      call, state: italian, connection: PSTools.Connection(contribute: { _ in nil }, registerPresets: {}, ask: { _, _, _ in .failure("") }))
    let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    let json = (try! JSONSerialization.jsonObject(with: Data((object["text"] as? String ?? "").utf8))) as! [String: Any]
    #expect(json["seamProblem"] as? String == L.text(.seamNoResult, italian: false))
    #expect(italian.italian == true)
  }

  @Test func anInactivePlugInRefusesEverything() async {
    state.active = false
    for tool in PSTools.declarations.map(\.name) {
      #expect(await call(tool, ["image": picture(), "sticker": 1, "text": "x"]).isError, Comment(rawValue: tool))
    }
    #expect(spy.bodies.isEmpty && state.doc.stickers.isEmpty)
  }

  // MARK: Stickers

  @Test func aStickerIsAddedWithItsValuesAndBecomesTheLastLayer() async {
    let first = await call("add_sticker", ["image": picture("a.png"), "yaw": 90, "pitch": 10, "fov": 40, "opacity": 0.5])
    #expect(!first.isError, Comment(rawValue: first.text))
    #expect(first.stickers.count == 1 && first.stickers[0]["yaw"] as? Double == 90 && first.stickers[0]["fov"] as? Double == 40)
    #expect(first.stickers[0]["opacity"] as? Double == 0.5 && first.stickers[0]["name"] as? String == "a.png")
    let second = await call("add_sticker", ["image": picture("b.png")])
    #expect(second.stickers.map { $0["name"] as? String } == ["a.png", "b.png"] && second.stickers[1]["sticker"] as? Int == 2)
    #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent(state.doc.stickers[0].file).path))
  }

  @Test func badArgumentsAddNothing() async {
    for bad in [["yaw": 181], ["pitch": 90], ["fov": 4], ["fov": 171], ["opacity": 1.5], ["rotation": -200]] as [[String: Any]] {
      #expect(await call("add_sticker", bad.merging(["image": picture()]) { a, _ in a }).isError, Comment(rawValue: "\(bad)"))
    }
    #expect(await call("add_sticker", ["image": "/no/such.png"]).isError)
    #expect(await call("add_sticker").isError)
    let notAPicture = TestImages.tempFolder().appendingPathComponent("x.png")
    try? Data([1, 2, 3]).write(to: notAPicture)
    #expect(await call("add_sticker", ["image": notAPicture.path]).isError)
    #expect(state.doc.stickers.isEmpty)
  }

  @Test func withoutAProjectNothingIsAdded() async {
    let bare = PSState(italian: false)
    bare.active = true
    let call = DTHubToolCall(Data(#"{"type":"tool.call","tool":"add_sticker","arguments":{"image":"\#(picture())"}}"#.utf8))!
    let data = await PSTools.handle(
      call, state: bare, connection: PSTools.Connection(contribute: { _ in nil }, registerPresets: {}, ask: { _, _, _ in .failure("") }))
    #expect((try! JSONSerialization.jsonObject(with: data) as! [String: Any])["isError"] as? Bool == true && bare.doc.stickers.isEmpty)
  }

  @Test func setStickerChangesOnlyWhatIsNamedAndMovesLayers() async {
    _ = await call("add_sticker", ["image": picture("a.png")])
    _ = await call("add_sticker", ["image": picture("b.png")])
    _ = await call("add_sticker", ["image": picture("c.png")])
    let changed = await call("set_sticker", ["sticker": 2, "yaw": -45, "visible": false, "layer": 1])
    #expect(!changed.isError)
    #expect(changed.stickers.map { $0["name"] as? String } == ["b.png", "a.png", "c.png"])
    #expect(changed.stickers[0]["yaw"] as? Double == -45 && changed.stickers[0]["visible"] as? Bool == false)
    #expect(changed.stickers[1]["visible"] as? Bool == true && changed.stickers[1]["yaw"] as? Double == 0)
    _ = await call("set_sticker", ["sticker": 1, "layer": 3])
    #expect(state.doc.stickers.map(\.name) == ["a.png", "c.png", "b.png"])
  }

  @Test func badStickerArgumentsChangeNothing() async {
    _ = await call("add_sticker", ["image": picture("a.png")])
    let before = state.doc.stickers
    #expect(await call("set_sticker", ["sticker": 2]).isError)
    #expect(await call("set_sticker", ["sticker": 0]).isError)
    #expect(await call("set_sticker", ["sticker": 1, "yaw": 10, "fov": 500]).isError)
    #expect(await call("set_sticker", ["sticker": 1, "layer": 4]).isError)
    #expect(state.doc.stickers == before)
  }

  @Test func removeAndClear() async {
    _ = await call("add_sticker", ["image": picture("a.png")])
    _ = await call("add_sticker", ["image": picture("b.png")])
    #expect(await call("remove_sticker", ["sticker": 5]).isError)
    let removed = await call("remove_sticker", ["sticker": 1])
    #expect(!removed.isError && removed.stickers.map { $0["name"] as? String } == ["b.png"])
    #expect(!(await call("clear_stickers")).isError && state.doc.stickers.isEmpty)
    #expect(await call("remove_sticker", ["sticker": 1]).isError)
  }

  // MARK: Description

  @Test func theDescriptionAndTheModeAreSetSeparately() async {
    #expect(!(await call("set_description", ["text": "a quiet harbour at dawn"])).isError && state.doc.description == "a quiet harbour at dawn")
    #expect(!(await call("set_description", ["mode": "fast"])).isError && state.doc.mode == .fast && state.doc.description == "a quiet harbour at dawn")
    #expect(await call("set_description").isError)
    #expect(await call("set_description", ["mode": "slow"]).isError)
    #expect(await call("set_description", ["text": String(repeating: "a", count: PSTools.maxDescription + 1)]).isError)
    #expect(state.doc.mode == .fast && state.doc.description == "a quiet harbour at dawn")
    #expect(!(await call("set_description", ["text": ""])).isError && state.doc.description.isEmpty)
  }

  @Test func improveRewritesTheDescriptionAndUndoBringsItBack() async {
    #expect(await call("improve_description").isError)
    _ = await call("set_description", ["text": "una valle al tramonto"])
    spy.llm = [.text("A mountain valley at sunset, warm light, pine forest.")]
    let answer = await call("improve_description")
    #expect(!answer.isError, Comment(rawValue: answer.text))
    #expect(state.doc.description == "A mountain valley at sunset, warm light, pine forest." && answer.json["canUndoImprove"] as? Bool == true)
    #expect(state.isImproving == false && spy.asked.count == 1)
    let undone = await call("undo_improve")
    #expect(!undone.isError && state.doc.description == "una valle al tramonto")
    #expect(await call("undo_improve").isError)
  }

  @Test func aFailedImproveIsAnErrorAndKeepsTheText() async {
    _ = await call("set_description", ["text": "una valle"])
    spy.llm = [.failure("no model loaded")]
    let answer = await call("improve_description")
    #expect(answer.isError && answer.text.contains("no model loaded") && state.doc.description == "una valle")
  }

  // MARK: Send

  @Test func sendPutsTheCanvasInTheGenerationTabAndDoesNotRun() async throws {
    _ = await call("add_sticker", ["image": picture("a.png")])
    _ = await call("set_description", ["text": "a quiet harbour at dawn", "mode": "fast"])
    let answer = await call("send_panorama")
    #expect(!answer.isError && !answer.startsRun && answer.json["sent"] as? Bool == true, Comment(rawValue: answer.text))
    #expect(spy.presetCalls == 1 && spy.bodies.count == 1)
    let body = try #require(spy.bodies.last)
    #expect(body["preset"] as? String == "PAN · 360 ERP Fast" && body["strength"] as? Double == 1 && body["pipeline"] == nil)
    #expect((body["fields"] as? [String: Any])?["prompt"] as? String == "a quiet harbour at dawn")
    #expect(answer.json["preset"] as? String == "PAN · 360 ERP Fast")
  }

  @Test func sendNeedsAVisibleStickerAndTheAppMayRefuse() async {
    let none = await call("send_panorama")
    #expect(none.isError && spy.bodies.isEmpty)
    _ = await call("add_sticker", ["image": picture("a.png")])
    _ = await call("set_sticker", ["sticker": 1, "visible": false])
    #expect(await call("send_panorama").isError)
    _ = await call("set_sticker", ["sticker": 1, "visible": true])
    spy.answer = ["type": "ok", "problems": ["preset: there is no preset named “PAN · 360 ERP”."]]
    let problems = await call("send_panorama")
    #expect(problems.isError && problems.text.contains("PAN · 360 ERP"))
    spy.answer = ["type": "error", "text": "DT Hub is busy"]
    #expect((await call("send_panorama")).text.contains("busy"))
    spy.answer = nil
    #expect(await call("send_panorama").isError && state.isSending == false)
  }

  @Test func aModelThatIsNotABaseOneIsWarnedAbout() async {
    state.apply(context: Data(#"{"type":"context","model":"flux_2_klein_9b_i8x.ckpt","tempFolder":"\#(TestImages.tempFolder().path)"}"#.utf8))
    _ = await call("add_sticker", ["image": picture("a.png")])
    let answer = await call("send_panorama")
    #expect(!answer.isError && answer.json["warning"] as? String != nil)
  }

  // MARK: The seam

  @Test func fixSeamProposesTheGuidedPassAndAsksTheAppToRun() async throws {
    apply(result: TestImages.file(TestImages.solid(1024, 512, 30, 60, 90), in: TestImages.tempFolder(), name: "r.png", type: "public.png"))
    let answer = await call("fix_seam")
    #expect(!answer.isError && answer.startsRun, Comment(rawValue: answer.text))
    let pipeline = try #require(spy.bodies.last?["pipeline"] as? [String: Any])
    #expect(pipeline["guided"] as? Bool == true && pipeline["passes"] as? Int == 1)
    #expect(answer.json["passes"] as? Int == 1 && state.isSeamPrepared)
  }

  @Test func fixSeamNeedsAResultOfTheRightShape() async {
    let none = await call("fix_seam")
    #expect(none.isError && !none.startsRun && spy.bodies.isEmpty)
    apply(result: TestImages.file(TestImages.solid(1000, 1024, 1, 2, 3), in: TestImages.tempFolder(), name: "sq.png", type: "public.png"))
    #expect(await call("fix_seam").isError)
    #expect(spy.bodies.isEmpty)
  }

  @Test func fixSeamAsksForTheModelOfThePreset() async throws {
    apply(result: TestImages.file(TestImages.solid(1024, 512, 30, 60, 90), in: TestImages.tempFolder(), name: "r.png", type: "public.png"))
    let preset = state.presetsFolder.appendingPathComponent("\(PSSeam.presetName).json")
    try Data(#"{"model":"another_model_i8x.ckpt"}"#.utf8).write(to: preset)
    let refused = await call("fix_seam")
    #expect(refused.isError && !refused.startsRun && refused.text.contains("another_model_i8x.ckpt") && spy.bodies.isEmpty)
    state.apply(context: Data(#"{"type":"context","model":"another_model_i8x.ckpt","tempFolder":"\#(TestImages.tempFolder().path)","lastResult":{"path":"\#(state.lastResultPath ?? "")","name":"r.png"}}"#.utf8))
    #expect((await call("fix_seam")).startsRun)
  }

  @Test func theAppRefusingTheCorrectionIsAnErrorAndNeverStartsARun() async {
    apply(result: TestImages.file(TestImages.solid(1024, 512, 30, 60, 90), in: TestImages.tempFolder(), name: "r.png", type: "public.png"))
    spy.answer = ["type": "error", "text": "DT Hub is busy"]
    let answer = await call("fix_seam")
    #expect(answer.isError && !answer.startsRun && answer.text.contains("busy") && state.isSeamPrepared == false)
  }

  @Test func theToolCallMessageReachesThePlugIn() async throws {
    let plugin = Panorama360Plugin(dataFolder: TestImages.tempFolder())
    let reply = await plugin.handle(Data(#"{"type":"tool.call","tool":"get_status","arguments":{}}"#.utf8))
    let object = try #require(reply.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(object["type"] as? String == "unsupported")
  }
}
