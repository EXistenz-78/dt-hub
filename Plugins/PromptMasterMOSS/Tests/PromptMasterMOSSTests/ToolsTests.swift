import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterMOSS

@MainActor
@Suite("The MCP tools")
struct ToolsTests {
  let state: MossState

  init() {
    state = MossState(
      data: StateTests.data,
      promptFolder: MossPrompts.folder(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent("moss-tools-\(UUID().uuidString)")),
      store: MossStore(storage: MemoryStorage()), italian: false, shuffler: { _, _ in [] })
    state.active = true
    state.update(generationSize: PixelSize(width: 1024, height: 640))
    state.update(models: [], family: "moss_image")
  }

  func call(_ tool: String, _ arguments: [String: Any] = [:], write: MossTools.WriteReport? = nil, send: PromptSender.Outcome? = nil) async -> (text: String, isError: Bool) {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let answer = await MossTools.handle(call, state: state, actions: .init(write: { write }, send: { send }))
    let object = try! JSONSerialization.jsonObject(with: answer) as! [String: Any]
    return (object["text"] as? String ?? "", object["isError"] as? Bool ?? false)
  }

  func object(_ text: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(text.drop { $0 != "{" }.utf8))) as? [String: Any] ?? [:]
  }

  @Test func theDeclarationsAreWellFormedAndNoneStartsAGeneration() throws {
    for tool in MossTools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20 && tool.level != .generate)
    }
    #expect(MossTools.declarations.filter { $0.level == .read }.map(\.name) == ["get_status", "search_terms"])
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(MossTools.declarations)) is [[String: Any]])
    #expect(MossPlugin(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent("moss-p-\(UUID().uuidString)"), store: MossStore(storage: MemoryStorage())).manifest.tools?.map(\.name) == MossTools.declarations.map(\.name))
  }

  @Test func theModelWrittenWithIsTheOneAssignedToTheFamily() {
    func lm(_ n: String, _ f: String, _ u: String) -> DTHubLanguageModel { DTHubLanguageModel(name: n, path: "/m/\(n)", supportsImages: false, family: f, use: u) }
    #expect(state.writeModel == nil)
    state.update(models: [lm("g", "*", "both"), lm("moss", "moss_image", "enhance"), lm("d", "moss_image", "describe")], family: "moss_image")
    #expect(state.writeModel == "moss")
  }

  @Test func briefAndElementsChangeTheTabAndSendNeedsNoProblems() async throws {
    let found = object(await call("search_terms", ["limit": 2]).text)
    let id = try #require((found["terms"] as? [[String: Any]])?.first?["id"] as? String)
    #expect(!(await call("set_brief", ["description": "A scene.", "add_terms": id, "canvas": "collage"])).isError)
    #expect(state.document.description == "A scene." && state.isChosen(id) && state.document.canvas == .collage)
    #expect(await call("send_to_generation", send: .init(status: "Sent", sent: true)).isError)  // no elements
    let added = object(await call("add_element", ["label": "text", "caption": "A sign", "text": "OPEN", "x0": 0.1, "y0": 0.1, "x1": 0.5, "y1": 0.5]).text)
    let itemID = try #require(added["id"] as? Int)
    #expect(state.document.items.first?.text == "OPEN" && state.document.items.first?.label == .text)
    #expect(!(await call("set_element", ["id": itemID, "tags": "neon, sign", "x1": 0.6, "x0": 0.2, "y0": 0.2, "y1": 0.7])).isError)
    #expect(state.document.items.first?.tags == "neon, sign")
    let status = object(await call("get_status").text)
    #expect(status["canSend"] as? Bool == true && (status["json"] as? String)?.isEmpty == false)
    #expect(!(await call("send_to_generation", send: .init(status: "Sent", sent: true))).isError)
    #expect(await call("send_to_generation", send: .init(status: "Refused", sent: false)).isError)
    #expect(!(await call("remove_element", ["id": itemID])).isError && state.document.items.isEmpty)
  }

  @Test func badInputIsRefusedAndChangesNothing() async {
    state.document.description = "keep"
    #expect(await call("set_brief", ["description": "new", "add_terms": "nope"]).isError && state.document.description == "keep")
    #expect(await call("set_brief", ["mode": "sepia"]).isError)
    #expect(await call("set_brief", ["canvas": "wall"]).isError)
    #expect(await call("add_element", ["caption": "x"]).isError)
    #expect(await call("add_element", ["x0": 0.1, "y0": 0.1]).isError)
    #expect(await call("add_element", ["x0": 0.1, "y0": 0.1, "x1": 0.11, "y1": 0.11]).isError)
    #expect(await call("add_element", ["x0": 0.1, "y0": 0.1, "x1": 2, "y1": 0.5]).isError)
    #expect(await call("add_element", ["label": "blob", "x0": 0.1, "y0": 0.1, "x1": 0.5, "y1": 0.5]).isError)
    #expect(await call("set_element", ["id": 9, "caption": "x"]).isError && state.document.items.isEmpty)
  }

  @Test func writingReportsWhatHappened() async {
    #expect(await call("write_with_llm").isError)
    state.document.description = "a scene"
    let ok = await call("write_with_llm", write: .init(wrote: true, status: "Done"))
    #expect(!ok.isError && object(ok.text)["status"] as? String == "Done")
    #expect(await call("write_with_llm", write: .init(wrote: false, status: "No language model.")).isError)
    state.active = false
    #expect(await call("write_with_llm", write: .init(wrote: true, status: "Done")).isError)
  }
}
