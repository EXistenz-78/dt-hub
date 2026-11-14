import DTHubPluginKit
import Foundation
import Testing

@testable import Flux3Editing

@MainActor
@Suite("Flux3 Editing tools")
struct FEToolsTests {
  @MainActor
  final class Spy {
    var contributions: [[String: Any]] = []
    var answer: [String: Any]? = ["type": "ok"]
    var asked: [(prompt: String, model: String?)] = []
    var llm: DTHubLLMAnswer = .text("")
  }

  let spy = Spy()
  let state: EditState

  init() throws {
    state = EditState(store: EditStore(storage: MemoryStorage()), italian: false, imageSize: { _ in CGSize(width: 300, height: 200) })
    state.active = true
    state.update(context: try Self.context())
  }

  static func context(start: String? = "/s/start.png", moodboard: [String] = ["/s/a.png", "/s/b.png"]) throws -> DTHubContext {
    var json = #"{"type":"context","tempFolder":"/t","parameters":{"width":2048,"height":1664},"family":"flux3_5b""#
    if let start { json += #","startImage":"\#(start)""# }
    if !moodboard.isEmpty { json += #","moodboard":[\#(moodboard.map { "\"\($0)\"" }.joined(separator: ","))]"# }
    return try JSONDecoder().decode(DTHubContext.self, from: Data((json + "}").utf8))
  }

  struct Answer {
    var text: String
    var isError: Bool
    var startsRun: Bool
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:] }
    var elements: [[String: Any]] { json["elements"] as? [[String: Any]] ?? [] }
  }

  func call(_ tool: String, _ arguments: [String: Any] = [:]) async -> Answer {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let spy = self.spy
    let state = self.state
    let connection = FETools.Connection(
      improve: {
        await state.improve(ask: { prompt, _, _, _, model in
          spy.asked.append((prompt, model))
          return spy.llm
        })
      },
      sender: EditSender(contribute: { spy.contributions.append($0); return spy.answer }, italian: false))
    let data = await FETools.handle(call, state: state, connection: connection)
    let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    return Answer(
      text: object["text"] as? String ?? "", isError: object["isError"] as? Bool ?? false,
      startsRun: object["startsRun"] as? Bool ?? false)
  }

  // MARK: Declarations

  @Test func theDeclarationsAreWellFormedAndInTheManifest() throws {
    for tool in FETools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20)
    }
    #expect(
      FETools.declarations.map(\.name) == [
        "get_status", "set_prompt_text", "set_element", "remove_element", "clear_edit", "improve_prompt", "undo_improve", "send_prompt",
      ])
    // Nothing generates: the agent runs through the app's own run.
    #expect(FETools.declarations.map(\.level) == [.read] + Array(repeating: .edit, count: 7))
    let set = try #require(FETools.declarations.first { $0.name == "set_element" })
    #expect(set.parameters.first { $0.name == "id" }?.required == true)
    #expect(set.parameters.first { $0.name == "kind" }?.values == ["new", "existing", "move", "remove", "from_reference"])
    #expect(try #require(FETools.declarations.first { $0.name == "improve_prompt" }).timeout == 600)
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(FETools.declarations)) is [[String: Any]])
    let plugin = Flux3EditingPlugin()
    #expect(plugin.manifest.tools?.count == 8 && plugin.manifest.version == "1.3")
    #expect(plugin.manifest.families == ["flux3_5b"])
  }

  // MARK: Reading

  @Test func theStatusShowsThePicturesTheBoxFormatAndWhatStopsSend() async {
    let answer = await call("get_status")
    #expect(!answer.isError && !answer.startsRun)
    let json = answer.json
    #expect(json["hasStartImage"] as? Bool == true && json["canSend"] as? Bool == false)
    #expect((json["references"] as? [[String: Any]])?.map { $0["file"] as? String } == ["a.png", "b.png"])
    #expect((json["problems"] as? [String])?.contains("No element yet.") == true)
    #expect((json["canvas"] as? [String: Int]) == ["width": 2048, "height": 1664])
    #expect(json["improveMode"] as? String == "standard")
    #expect((json["note"] as? String)?.contains("data") == true)
  }

  @Test func anInactivePlugInRefusesEverything() async {
    state.active = false
    for tool in FETools.declarations.map(\.name) {
      #expect(await call(tool, ["id": "x", "text": "y"]).isError, Comment(rawValue: tool))
    }
    #expect(spy.contributions.isEmpty && state.document.elements.isEmpty)
  }

  // MARK: Elements

  @Test func aNewElementNeedsItsBoxAndTheOtherKindsTheirs() async {
    let added = await call("set_element", ["id": "lamp_1", "kind": "new", "tgt_bbox": "[550, 300, 720, 550]", "description": "A brass lamp."])
    #expect(!added.isError)
    #expect(added.elements.first?["tgt_bbox"] as? [Int] == [550, 300, 720, 550] && added.elements.first?["from"] is NSNull)
    #expect(await call("set_element", ["id": "n", "kind": "new"]).isError)
    #expect(await call("set_element", ["id": "n", "kind": "new", "tgt_bbox": "10,10,200,200", "src_bbox": "10,10,200,200"]).isError)
    #expect(await call("set_element", ["id": "e", "kind": "existing", "tgt_bbox": "10,10,200,200"]).isError)
    #expect(await call("set_element", ["id": "m", "kind": "move", "src_bbox": "10,10,200,200"]).isError)
    #expect(state.document.elements.map(\.id) == ["lamp_1"])
    let moved = await call("set_element", ["id": "m", "kind": "move", "src_bbox": "10,10,200,200", "tgt_bbox": "300,300,500,500"])
    #expect(!moved.isError && state.document.elements.map(\.id) == ["lamp_1", "m"])
    let removed = await call("set_element", ["id": "r", "kind": "remove", "src_bbox": "[600, 600, 800, 900]"])
    #expect(removed.elements.last?["tgt_bbox"] is NSNull && removed.elements.last?["from"] as? String == "ref_image_0")
  }

  @Test func anElementFromAReferenceUsesThePictureByItsNumber() async {
    let answer = await call(
      "set_element",
      ["id": "vase", "kind": "from_reference", "reference": 2, "src_bbox": "[100, 100, 400, 400]", "tgt_bbox": "[500, 500, 700, 700]", "description": "A vase."])
    #expect(!answer.isError)
    #expect(state.document.elements.first?.refFile == "b.png" && answer.elements.first?["from"] as? String == "ref_image_2")
    #expect(await call("set_element", ["id": "v2", "kind": "from_reference", "src_bbox": "10,10,200,200", "tgt_bbox": "10,10,200,200"]).isError)
    #expect(await call("set_element", ["id": "v3", "kind": "from_reference", "reference": 3, "src_bbox": "10,10,200,200", "tgt_bbox": "10,10,200,200"]).isError)
    #expect(await call("set_element", ["id": "v4", "kind": "new", "reference": 1, "tgt_bbox": "10,10,200,200"]).isError)
    #expect(state.document.elements.count == 1)
  }

  @Test func boxesAreStrictAndNothingChangesOnABadOne() async {
    for bad in ["10,10,200", "0,0,0,0", "[10, 10, 5, 200]", "[0, 0, 1001, 300]", "[10, 10, 15, 200]", "[-5, 10, 200, 200]", "a b c d"] {
      #expect(await call("set_element", ["id": "x", "kind": "new", "tgt_bbox": bad]).isError, Comment(rawValue: bad))
    }
    #expect(state.document.elements.isEmpty)
    #expect((try? FETools.parseBox("b", "[0, 0, 1000, 1000]")) != nil && (try? FETools.parseBox("b", "100 200 300 400")) != nil)
  }

  @Test func idsAreCheckedAndUnique() async {
    for bad in ["", "a b", "a<b>", "x\ny", "ref_image_3", String(repeating: "a", count: 41)] {
      #expect(await call("set_element", ["id": bad, "kind": "new", "tgt_bbox": "10,10,200,200"]).isError, Comment(rawValue: bad))
    }
    #expect(!(await call("set_element", ["id": "a", "kind": "new", "tgt_bbox": "10,10,200,200"])).isError)
    #expect(!(await call("set_element", ["id": "b", "kind": "new", "tgt_bbox": "300,300,500,500"])).isError)
    #expect(await call("set_element", ["id": "b", "new_id": "a"]).isError)
    #expect(await call("set_element", ["id": "zzz", "description": "x"]).isError)
    #expect(!(await call("set_element", ["id": "b", "new_id": "c", "description": "A thing"])).isError)
    #expect(state.document.elements.map(\.id) == ["a", "c"] && state.document.elements[1].desc == "A thing")
  }

  @Test func anElementIsChangedPieceByPieceAndTheKindMayChange() async {
    _ = await call("set_element", ["id": "a", "kind": "new", "tgt_bbox": "[100, 100, 300, 300]", "description": "Old"])
    _ = await call("set_element", ["id": "a", "description": "New text"])
    #expect(state.document.elements[0].desc == "New text" && state.document.elements[0].tgt == BBox(y0: 100, x0: 100, y1: 300, x1: 300))
    let changed = await call("set_element", ["id": "a", "kind": "move"])
    #expect(!changed.isError && state.document.elements[0].kind == .move && state.document.elements[0].src != nil)
    #expect(await call("set_element", ["id": "a", "kind": "from_reference", "reference": 1]).isError)
    #expect(await call("set_element", ["id": "a", "reference": 1]).isError)
    _ = await call("set_element", ["id": "r", "kind": "from_reference", "reference": 1, "src_bbox": "10,10,200,200", "tgt_bbox": "10,10,200,200"])
    #expect(await call("set_element", ["id": "r", "kind": "move"]).isError)
    #expect(!(await call("set_element", ["id": "r", "reference": 2])).isError && state.document.element("r")?.refFile == "b.png")
  }

  @Test func theNumberOfElementsAndTheTextsAreLimited() async {
    for index in 0..<FETools.maxElements {
      #expect(!(await call("set_element", ["id": "e\(index)", "kind": "new", "tgt_bbox": "10,10,200,200"])).isError)
    }
    #expect(await call("set_element", ["id": "extra", "kind": "new", "tgt_bbox": "10,10,200,200"]).isError)
    #expect(await call("set_element", ["id": "e0", "description": String(repeating: "a", count: FETools.maxDescription + 1)]).isError)
    #expect(await call("set_prompt_text", ["text": String(repeating: "a", count: FETools.maxProse + 1)]).isError)
    #expect(await call("set_prompt_text").isError)
  }

  @Test func removeElementAndClear() async {
    _ = await call("set_element", ["id": "a", "kind": "new", "tgt_bbox": "10,10,200,200"])
    _ = await call("set_prompt_text", ["text": "Modify <ref_image_0> by adding <a>."])
    #expect(await call("remove_element", ["id": "nope"]).isError)
    #expect(!(await call("remove_element", ["id": "a"])).isError && state.document.elements.isEmpty)
    #expect(state.document.prose == "Modify <ref_image_0> by adding <a>.")
    _ = await call("set_element", ["id": "b", "kind": "new", "tgt_bbox": "10,10,200,200"])
    #expect(!(await call("clear_edit")).isError)
    #expect(state.document.elements.isEmpty && state.document.prose == EditDocument.defaultProse)
  }

  // MARK: Improve and send

  @Test func improveNeedsSomethingToImproveAndReplacesTheTexts() async {
    #expect(await call("improve_prompt").isError)
    _ = await call("set_prompt_text", ["text": "Modify <ref_image_0> by adding <lamp>."])
    _ = await call("set_element", ["id": "lamp", "kind": "new", "tgt_bbox": "[500, 300, 700, 500]", "description": "a lamp"])
    spy.llm = .text("## prose\nModify <ref_image_0> by adding the table lamp <lamp> on the sideboard.\n\n## element: lamp\nA brass table lamp.")
    let answer = await call("improve_prompt")
    #expect(!answer.isError, Comment(rawValue: answer.text))
    #expect(state.document.prose == "Modify <ref_image_0> by adding the table lamp <lamp> on the sideboard.")
    #expect(state.document.elements[0].desc == "A brass table lamp." && answer.json["canUndoImprove"] as? Bool == true)
    #expect(state.isWriting == false && spy.asked.count == 1)
    let undone = await call("undo_improve")
    #expect(!undone.isError && state.document.prose == "Modify <ref_image_0> by adding <lamp>." && state.document.elements[0].desc == "a lamp")
    #expect(await call("undo_improve").isError)
  }

  @Test func aFailedImproveIsAnErrorAndKeepsTheTexts() async {
    _ = await call("set_prompt_text", ["text": "Modify <ref_image_0> by adding <lamp>."])
    spy.llm = .failure("no model loaded")
    let answer = await call("improve_prompt")
    #expect(answer.isError && state.document.prose == "Modify <ref_image_0> by adding <lamp>." && state.isWriting == false)
  }

  @Test func sendNeedsAStartImageAnElementAndTheirDescriptions() async {
    #expect(await call("send_prompt").isError)
    _ = await call("set_element", ["id": "lamp", "kind": "new", "tgt_bbox": "[500, 300, 700, 500]"])
    let noDescription = await call("send_prompt")
    #expect(noDescription.isError && noDescription.text.contains("lamp has no description"))
    state.update(context: try! Self.context(start: nil))
    _ = await call("set_element", ["id": "lamp", "description": "A lamp"])
    #expect((await call("send_prompt")).text.contains("No start image"))
    #expect(spy.contributions.isEmpty)
  }

  @Test func sendPutsThePromptInTheFieldAndDoesNotRun() async throws {
    _ = await call("set_prompt_text", ["text": "Modify <ref_image_0> by adding <lamp>."])
    _ = await call("set_element", ["id": "lamp", "kind": "new", "tgt_bbox": "[500, 300, 700, 500]", "description": "A brass lamp."])
    let answer = await call("send_prompt")
    #expect(!answer.isError && !answer.startsRun && answer.json["sent"] as? Bool == true)
    let fields = try #require(spy.contributions.last?["fields"] as? [String: Any])
    let prompt = try #require(fields["prompt"] as? String)
    #expect(prompt.hasPrefix("Modify <ref_image_0> by adding <lamp>.") && prompt.contains("\"src_bbox\": null") && prompt.contains("[500, 300, 700, 500]"))
    #expect(fields["negativePrompt"] as? String == "" && state.isSending == false)
  }

  @Test func theAppRefusingTheFieldIsAnError() async {
    _ = await call("set_element", ["id": "lamp", "kind": "new", "tgt_bbox": "[500, 300, 700, 500]", "description": "A lamp"])
    spy.answer = ["type": "error", "text": "DT Hub is busy"]
    let answer = await call("send_prompt")
    #expect(answer.isError && answer.text.contains("busy") && state.isSending == false)
    spy.answer = nil
    #expect(await call("send_prompt").isError)
  }

  @Test func aBusyPlugInRefusesChanges() async {
    state.isWriting = true
    #expect(await call("set_prompt_text", ["text": "x"]).isError)
    #expect(await call("set_element", ["id": "a", "kind": "new", "tgt_bbox": "10,10,200,200"]).isError)
    let results = [await call("send_prompt"), await call("improve_prompt"), await call("clear_edit")]
    let allRefused = results.allSatisfy { $0.isError }
    #expect(allRefused)
  }

  @Test func theToolCallMessageReachesThePlugIn() async throws {
    let reply = await Flux3EditingPlugin().handle(Data(#"{"type":"tool.call","tool":"get_status","arguments":{}}"#.utf8))
    let object = try #require(reply.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(object["type"] as? String == "unsupported")
  }
}
