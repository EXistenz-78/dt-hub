import DTHubPluginKit
import Foundation
import Testing

@testable import CharacterSheet

@MainActor
@Suite("Character Sheet tools")
struct CSToolsTests {
  let spy = Spy()
  let state: CSState
  let folder: URL

  init() {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("cs-tools-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    state = CSState(store: CSSettingsStore(folder: folder))
    state.active = true
    let context = #"{"type":"context","tempFolder":"\#(folder.path)","family":"qwen_image_2.1","languageModels":[{"name":"vlm","path":"/models/vlm","supportsImages":true},{"name":"text-only","path":"/models/t","supportsImages":false}]}"#
    state.update(from: try! JSONDecoder().decode(DTHubContext.self, from: Data(context.utf8)))
    spy.templates = [
      .master: .success("MASTER"), .staticPrompt: .success("Sheet of {{name}}"),
      .masterExpressions: .success("MASTER EXPR"), .staticExpressions: .success("Expressions of {{name}}"),
      .masterPoses: .success("MASTER POSES"), .staticPoses: .success("Poses of {{name}}"),
    ]
  }

  func runner() -> CSRunner {
    let spy = spy
    return CSRunner(
      contribute: { body in spy.bodies.append(body); return spy.nextContributeAnswer() },
      ask: { request in spy.requests.append(request); return spy.llmAnswer },
      copyImage: { source, tempFolder in spy.copied.append((source, tempFolder)); return tempFolder + "/copied.png" },
      readTemplate: { spy.templates[$0] ?? .failure(.missing($0)) },
      readPESystem: { _ in spy.peSystem },
      now: { spy.nextDate() }, templatesFolder: "/tpl", italian: false)
  }

  struct Answer {
    var text: String
    var isError: Bool
    var startsRun: Bool
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:] }
  }

  func call(_ tool: String, _ arguments: [String: Any] = [:]) async -> Answer {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let data = await CSTools.handle(call, state: state, runner: runner())
    let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    return Answer(
      text: object["text"] as? String ?? "", isError: object["isError"] as? Bool ?? false,
      startsRun: object["startsRun"] as? Bool ?? false)
  }

  func picture() -> String {
    let path = folder.appendingPathComponent("hero.png").path
    FileManager.default.createFile(atPath: path, contents: Data([1, 2, 3]))
    return path
  }

  // MARK: Declarations

  @Test func theDeclarationsAreWellFormedAndInTheManifest() throws {
    for tool in CSTools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20)
    }
    #expect(CSTools.declarations.map(\.name) == ["get_status", "prepare_sheet"])
    // Nothing generates: the agent runs through the app's own run.
    #expect(CSTools.declarations.map(\.level) == [.read, .edit])
    let prepare = try #require(CSTools.declarations.last)
    #expect(prepare.parameters.first { $0.name == "image" }?.format == "image")
    #expect(prepare.parameters.first { $0.name == "kind" }?.values == ["base", "expressions", "poses"])
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(CSTools.declarations)) is [[String: Any]])
    let plugin = CharacterSheetPlugin()
    #expect(plugin.manifest.tools?.count == 2)
    #expect(plugin.manifest.version == "1.3")
    #expect(plugin.manifest.families == ["qwen_image_2.1"])
  }

  // MARK: Reading

  @Test func theStatusShowsTheTabAndOnlyVisionModels() async {
    let answer = await call("get_status")
    #expect(!answer.isError && !answer.startsRun)
    let json = answer.json
    #expect(json["kind"] as? String == "base" && json["hasPicture"] as? Bool == false)
    #expect(json["visionModels"] as? [String] == ["vlm"] && json["model"] as? String == "vlm")
    #expect((json["canvas"] as? [String: Int]) == ["width": 2048, "height": 1536])
    #expect((json["note"] as? String)?.contains("data") == true)
  }

  @Test func aToolOfAnInactivePlugInOrWithoutContextIsRefused() async {
    state.active = false
    #expect(await call("get_status").isError)
    #expect(await call("prepare_sheet", ["static": true]).isError)
    let bare = CSState(store: CSSettingsStore(folder: folder.appendingPathComponent("x")))
    bare.active = true
    let probe = DTHubToolCall(Data(#"{"type":"tool.call","tool":"get_status","arguments":{}}"#.utf8))!
    let data = await CSTools.handle(probe, state: bare, runner: runner())
    #expect((try! JSONSerialization.jsonObject(with: data) as! [String: Any])["isError"] as? Bool == true)
    #expect(spy.bodies.isEmpty)
  }

  // MARK: Preparing

  @Test func aStaticSheetPutsThePictureTheSizeAndThePromptAndDoesNotRun() async {
    let answer = await call("prepare_sheet", ["image": picture(), "name": "Mira", "kind": "poses", "static": true])
    #expect(!answer.isError && !answer.startsRun)
    #expect(spy.kinds == ["moodboard", "size", "prompt"])
    #expect(spy.writtenPrompt == "Poses of Mira")
    #expect(spy.requests.isEmpty)
    let json = answer.json
    #expect(json["prepared"] as? Bool == true && json["prompt"] as? String == "Poses of Mira")
    #expect(state.kind == .poses && state.name == "Mira" && state.useStatic)
    #expect(state.busy == false)
    #expect((await call("get_status")).json["lastPrompt"] as? String == "Poses of Mira")
  }

  @Test func theLanguageModelWritesThePromptAndTheAnswerIsData() async {
    spy.llmAnswer = .text("A long brief for the sheet")
    let answer = await call("prepare_sheet", ["image": picture(), "name": "Mira", "static": false, "model": "vlm"])
    #expect(!answer.isError && !answer.startsRun)
    #expect(spy.requests.count == 1 && spy.requests[0].model == "vlm")
    #expect(spy.writtenPrompt == "A long brief for the sheet")
    #expect(answer.json["model"] as? String == "vlm")
  }

  @Test func argumentsLeftOutStayAsTheyAre() async {
    _ = await call("prepare_sheet", ["image": picture(), "name": "Mira", "kind": "expressions", "static": true])
    let again = await call("prepare_sheet", [:])
    #expect(!again.isError)
    #expect(state.kind == .expressions && state.name == "Mira" && state.useStatic)
    #expect(spy.writtenPrompt == "Expressions of Mira")
  }

  @Test func badArgumentsChangeNothingAndSendNothing() async {
    let before = state.job
    #expect(await call("prepare_sheet", ["kind": "bogus"]).isError)
    #expect(await call("prepare_sheet", ["name": String(repeating: "a", count: 101)]).isError)
    let unknown = await call("prepare_sheet", ["model": "text-only", "static": false])
    #expect(unknown.isError && unknown.text.contains("vlm"))
    #expect(await call("prepare_sheet", ["image": "/no/such/file.png", "static": true]).isError)
    #expect(state.job == before)
    #expect(spy.bodies.isEmpty)
  }

  @Test func withoutAPictureTheToolSaysSoAndNothingIsSent() async {
    let answer = await call("prepare_sheet", ["static": true])
    #expect(answer.isError && !answer.text.isEmpty)
    #expect(spy.bodies.isEmpty)
  }

  @Test func aFailureOfTheLanguageModelIsAnError() async {
    spy.llmAnswer = .failure("out of memory")
    let answer = await call("prepare_sheet", ["image": picture(), "static": false])
    #expect(answer.isError && answer.text.contains("out of memory"))
    #expect(state.busy == false)
  }

  @Test func theAppRefusingAFieldIsAnError() async {
    spy.contributeAnswers = [["type": "error", "text": "DT Hub is busy"]]
    let answer = await call("prepare_sheet", ["image": picture(), "static": true])
    #expect(answer.isError && answer.text.contains("busy"))
    #expect(state.busy == false)
  }

  @Test func aBusyPreparationIsRefused() async {
    #expect(state.beginPrepare())
    let answer = await call("prepare_sheet", ["image": picture(), "static": true])
    #expect(answer.isError && spy.bodies.isEmpty)
  }

  @Test func theToolCallMessageReachesThePlugIn() async throws {
    let reply = await CharacterSheetPlugin().handle(Data(#"{"type":"tool.call","tool":"get_status","arguments":{}}"#.utf8))
    let object = try #require(reply.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(object["type"] as? String == "unsupported")
  }
}
