import DTHubPluginKit
import Foundation
import Testing

@testable import Panorama360F3

@MainActor
@Suite("Pano 360 F3 tools")
struct PFToolsTests {
  @MainActor
  final class Spy {
    var bodies: [[String: Any]] = []
    var answer: [String: Any]? = ["type": "ok"]
    var presetsOffered = 0
    var llm: DTHubLLMAnswer = .text("A misty lake at dawn, soft pink light.")
    var asked = 0
  }

  let spy = Spy()
  let state = PFState(italian: false)
  let pictures = TestImages.tempFolder()
  let project = TestImages.tempFolder()

  init() {
    state.switchProject(folder: project)
    state.apply(context: Data(#"{"type":"context","tempFolder":"\#(TestImages.tempFolder().path)"}"#.utf8))
  }

  func picture(_ name: String = "a.png", width: Int = 40, height: Int = 30) -> String {
    TestImages.png(width: width, height: height, in: pictures, name: name).path
  }

  struct Answer {
    var text: String
    var isError: Bool
    var startsRun: Bool
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:] }
    var images: [[String: Any]] { json["images"] as? [[String: Any]] ?? [] }
  }

  func call(_ tool: String, _ arguments: [String: Any] = [:], state custom: PFState? = nil) async -> Answer {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let spy = self.spy
    let connection = PFTools.Connection(
      contribute: { spy.bodies.append($0); return spy.answer },
      registerPresets: { spy.presetsOffered += 1 },
      ask: { _, _, _ in spy.asked += 1; return spy.llm })
    let data = await PFTools.handle(call, state: custom ?? state, connection: connection)
    let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    return Answer(
      text: object["text"] as? String ?? "", isError: object["isError"] as? Bool ?? false,
      startsRun: object["startsRun"] as? Bool ?? false)
  }

  // MARK: Declarations

  @Test func theDeclarationsAreWellFormedAndInTheManifest() throws {
    for tool in PFTools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20)
    }
    #expect(
      PFTools.declarations.map(\.name) == [
        "get_status", "add_image", "remove_image", "set_image_visible", "move_image", "set_description", "set_size",
        "improve_description", "undo_improve", "make_panorama", "fix_seam",
      ])
    #expect(PFTools.declarations.map(\.level) == [.read] + Array(repeating: .edit, count: 8) + [.generate, .generate])
    let add = try #require(PFTools.declarations.first { $0.name == "add_image" })
    #expect(add.parameters.first { $0.name == "image" }?.format == "image")
    #expect(try #require(PFTools.declarations.first { $0.name == "improve_description" }).timeout == 600)
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(PFTools.declarations)) is [[String: Any]])
    let plugin = Panorama360F3Plugin(dataFolder: TestImages.tempFolder())
    #expect(plugin.manifest.tools?.count == 11 && plugin.manifest.version == "1.1")
    #expect(plugin.manifest.families == ["flux3_5b"])
  }

  // MARK: Reading and the Moodboard

  @Test func withoutAProjectEveryToolIsRefusedAndNothingIsSent() async {
    let bare = PFState(italian: false)
    for tool in PFTools.declarations.map(\.name) {
      let answer = await call(tool, ["image": picture(), "index": 1, "text": "x", "width": 1024, "visible": true, "to": 1], state: bare)
      #expect(answer.isError, Comment(rawValue: tool))
    }
    #expect(spy.bodies.isEmpty)
  }

  @Test func theStatusShowsThePicturesTheirNumbersAndWhatStopsTheJob() async {
    let empty = await call("get_status")
    #expect(!empty.isError && empty.json["canMake"] as? Bool == false && (empty.json["blocker"] as? String)?.contains("add_image") == true)
    #expect((empty.json["size"] as? [String: Int]) == ["width": 2048, "height": 1024])
    _ = await call("add_image", ["image": picture("a.png")])
    _ = await call("add_image", ["image": picture("b.png")])
    _ = await call("set_image_visible", ["index": 1, "visible": false])
    let answer = await call("get_status")
    #expect(answer.images.map { $0["name"] as? String } == ["a.png", "b.png"])
    #expect(answer.images[0]["number"] == nil && answer.images[1]["number"] as? Int == 1)
    #expect(answer.json["canMake"] as? Bool == true && answer.json["imagesOn"] as? Int == 1)
    #expect((answer.json["note"] as? String)?.contains("data") == true)
  }

  @Test func theWordsAnAgentReadsAreEnglishWhateverTheTabLanguage() async {
    let italian = PFState(italian: true)
    italian.switchProject(folder: TestImages.tempFolder())
    let answer = await call("get_status", state: italian)
    #expect(answer.json["seamBlocker"] as? String == L.text(.seamNoResult, italian: false))
    #expect(italian.italian == true)
  }

  @Test func addRemoveMoveAndTurnOffPictures() async {
    #expect(await call("add_image", ["image": "/no/such.png"]).isError)
    #expect(await call("add_image").isError)
    for name in ["a.png", "b.png", "c.png"] { _ = await call("add_image", ["image": picture(name)]) }
    #expect(state.doc.images.map(\.name) == ["a.png", "b.png", "c.png"])
    #expect(!(await call("move_image", ["index": 3, "to": 1])).isError)
    #expect(state.doc.images.map(\.name) == ["c.png", "a.png", "b.png"])
    #expect(!(await call("move_image", ["index": 1, "to": 3])).isError)
    #expect(state.doc.images.map(\.name) == ["a.png", "b.png", "c.png"])
    #expect(await call("move_image", ["index": 4, "to": 1]).isError)
    #expect(await call("remove_image", ["index": 0]).isError)
    let removed = state.doc.images[1]
    #expect(!(await call("remove_image", ["index": 2])).isError)
    #expect(state.doc.images.map(\.name) == ["a.png", "c.png"])
    #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent(removed.file).path))
    #expect(await call("set_image_visible", ["index": 1]).isError)
  }

  @Test func aNotImageFileIsRefusedAndTheListStays() async throws {
    let junk = pictures.appendingPathComponent("junk.png")
    try Data("not an image".utf8).write(to: junk)
    let answer = await call("add_image", ["image": junk.path])
    #expect(answer.isError && state.doc.images.isEmpty)
  }

  @Test func atMostNinePictures() async {
    for index in 0..<PFTools.maxImages { #expect(!(await call("add_image", ["image": picture("p\(index).png")])).isError) }
    #expect(await call("add_image", ["image": picture("extra.png")]).isError)
    #expect(state.doc.images.count == PFTools.maxImages)
  }

  @Test func descriptionAndSizeAreCheckedBeforeTheyChange() async {
    #expect(!(await call("set_description", ["text": "  A quiet harbour at dusk.  "])).isError)
    #expect(state.doc.description == "A quiet harbour at dusk.")
    #expect(await call("set_description", ["text": "starting from <image 1>"]).isError)
    #expect(await call("set_description", ["text": "create a 360 hdr beach"]).isError)
    #expect(await call("set_description", ["text": String(repeating: "a", count: PFTools.maxDescription + 1)]).isError)
    #expect(state.doc.description == "A quiet harbour at dusk.")
    #expect(!(await call("set_size", ["width": 4096])).isError && state.doc.size == PFSize(width: 4096, height: 2048))
    for bad in [1000, 1100, 9000, 512, 0] { #expect(await call("set_size", ["width": bad]).isError, Comment(rawValue: "\(bad)")) }
    #expect(state.doc.size == PFSize(width: 4096, height: 2048))
  }

  // MARK: Improve

  @Test func improveReplacesTheDescriptionAndUndoBringsItBack() async {
    _ = await call("add_image", ["image": picture()])
    _ = await call("set_description", ["text": "a lake"])
    let answer = await call("improve_description")
    #expect(!answer.isError && answer.json["description"] as? String == "A misty lake at dawn, soft pink light.")
    #expect(state.doc.description == "A misty lake at dawn, soft pink light." && state.isImproving == false)
    #expect(!(await call("undo_improve")).isError && state.doc.description == "a lake")
    #expect(await call("undo_improve").isError)
  }

  @Test func aRefusedAnswerOrAFailureIsAnErrorAndKeepsTheText() async {
    _ = await call("add_image", ["image": picture()])
    _ = await call("set_description", ["text": "a lake"])
    spy.llm = .text("create a 360 hdr lake")
    #expect(await call("improve_description").isError && state.doc.description == "a lake")
    spy.llm = .failure("no model")
    let failed = await call("improve_description")
    #expect(failed.isError && failed.text.contains("no model") && state.doc.description == "a lake")
  }

  // MARK: Generating

  @Test func makePanoramaProposesTheGuidedPipelineAndAsksTheAppToRun() async throws {
    _ = await call("add_image", ["image": picture()])
    _ = await call("set_size", ["width": 1024])
    let answer = await call("make_panorama")
    #expect(!answer.isError && answer.startsRun, Comment(rawValue: answer.text))
    #expect(spy.presetsOffered == 1)
    let pipeline = try #require(spy.bodies.last?["pipeline"] as? [String: Any])
    #expect(pipeline["guided"] as? Bool == true && pipeline["passes"] as? Int == 2)
    #expect(answer.json["passes"] as? Int == 2 && state.session != nil && state.isSending == false)
  }

  @Test func makePanoramaNeedsAPictureAndConfirmationForABigOne() async {
    let none = await call("make_panorama")
    #expect(none.isError && !none.startsRun && none.text.contains("add_image"))
    _ = await call("add_image", ["image": picture()])
    _ = await call("set_size", ["width": 6144])
    let refused = await call("make_panorama")
    #expect(refused.isError && !refused.startsRun && refused.text.contains("confirm_large"))
    #expect(spy.bodies.isEmpty)
    let accepted = await call("make_panorama", ["confirm_large": true])
    #expect(accepted.startsRun && spy.bodies.count == 1)
    _ = await call("set_size", ["width": 4096])
    state.session = nil
    #expect((await call("make_panorama")).startsRun)
  }

  @Test func theAppRefusingThePipelineIsAnErrorWithoutStartsRun() async {
    _ = await call("add_image", ["image": picture()])
    spy.answer = ["type": "error", "text": "DT Hub is busy"]
    let answer = await call("make_panorama")
    #expect(answer.isError && !answer.startsRun && answer.text.contains("busy") && state.session == nil)
    spy.answer = nil
    #expect(await call("make_panorama").isError)
    spy.answer = ["type": "ok", "problems": ["The model is not FLUX.3"]]
    #expect((await call("make_panorama")).text.contains("FLUX.3"))
  }

  @Test func fixSeamWorksOnAPictureGivenAndNeedsAValidPanorama() async throws {
    let none = await call("fix_seam")
    #expect(none.isError && !none.startsRun)
    let wrong = await call("fix_seam", ["image": picture("flat.png", width: 100, height: 100)])
    #expect(wrong.isError && !wrong.startsRun && spy.bodies.isEmpty)
    let pano = TestImages.png(width: 256, height: 128, in: pictures, name: "pano.png").path
    let answer = await call("fix_seam", ["image": pano])
    #expect(!answer.isError && answer.startsRun, Comment(rawValue: answer.text))
    let pipeline = try #require(spy.bodies.last?["pipeline"] as? [String: Any])
    #expect(pipeline["passes"] as? Int == 1 && pipeline["guided"] as? Bool == true)
    #expect(await call("fix_seam", ["image": "/no/such.png"]).isError)
  }

  @Test func theToolCallMessageReachesThePlugIn() async throws {
    let plugin = Panorama360F3Plugin(dataFolder: TestImages.tempFolder())
    let reply = await plugin.handle(Data(#"{"type":"tool.call","tool":"get_status","arguments":{}}"#.utf8))
    let object = try #require(reply.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(object["type"] as? String == "unsupported")
  }
}
