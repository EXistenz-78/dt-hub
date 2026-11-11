import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterF3

@MainActor
@Suite("The MCP tools")
struct ToolsTests {
  let state: F3State

  init() {
    state = F3State(
      promptFolder: F3Prompts.folder(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
      store: F3Store(storage: MemoryStorage()), italian: false, shuffler: { _, _ in [] }, sleep: { _ in try? await Task.sleep(for: .seconds(3600)) })
    state.active = true
    state.update(models: [], family: "flux3_5b")
  }

  func call(_ tool: String, _ arguments: [String: Any] = [:], write: F3Tools.WriteReport? = nil, send: PromptSender.Outcome? = nil) async -> (text: String, isError: Bool) {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let answer = await F3Tools.handle(call, state: state, actions: .init(write: { write }, send: { send }))
    let object = try! JSONSerialization.jsonObject(with: answer) as! [String: Any]
    return (object["text"] as? String ?? "", object["isError"] as? Bool ?? false)
  }

  func object(_ text: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(text.drop { $0 != "{" }.utf8))) as? [String: Any] ?? [:]
  }

  @Test func theDeclarationsAreWellFormedAndNoneStartsAGeneration() throws {
    for tool in F3Tools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20 && tool.level != .generate)
    }
    #expect(F3Tools.declarations.filter { $0.level == .read }.map(\.name) == ["get_status", "search_terms"])
    #expect(F3Plugin().manifest.tools?.map(\.name) == F3Tools.declarations.map(\.name))
  }

  @Test func compositionMakesElementsAndSetElementFillsThem() async throws {
    let found = object(await call("search_terms", ["limit": 2]).text)
    let id = try #require((found["terms"] as? [[String: Any]])?.first?["id"] as? String)
    let set = await call("set_brief", ["description": "a room", "composition": "A lamp <lamp_1> on a table.", "add_terms": id])
    #expect(!set.isError && state.document.element("lamp_1") != nil && state.document.selection.contains(id))
    let element = await call("set_element", ["id": "lamp_1", "description": "A brass lamp.", "y0": 100, "x0": 100, "y1": 400, "x1": 300])
    #expect(!element.isError && state.document.element("lamp_1")?.desc == "A brass lamp." && state.document.element("lamp_1")?.box.y1 == 400)
    let status = object(await call("get_status").text)
    #expect(status["canSend"] as? Bool == true && (status["problems"] as? [String])?.isEmpty == true)
  }

  @Test func badInputIsRefused() async {
    state.document.description = "keep"
    #expect(await call("set_brief", ["description": "new", "add_terms": "nope"]).isError && state.document.description == "keep")
    #expect(await call("set_brief", ["mode": "sepia"]).isError)
    #expect(await call("set_element", ["id": "ghost", "description": "x"]).isError)
    _ = await call("set_brief", ["composition": "A <a_1>."])
    #expect(await call("set_element", ["id": "a_1"]).isError)
    #expect(await call("set_element", ["id": "a_1", "y0": 1]).isError)
    #expect(await call("set_element", ["id": "a_1", "y0": 10, "x0": 10, "y1": 12, "x1": 12]).isError)
  }

  @Test func sendIsRefusedWhileThereAreProblemsAndOtherwiseGoes() async {
    #expect(await call("send_to_generation", send: .init(status: "Sent", sent: true)).isError)  // no elements
    _ = await call("set_brief", ["composition": "A lamp <lamp_1>."])
    #expect(await call("send_to_generation", send: .init(status: "Sent", sent: true)).isError)  // empty description
    _ = await call("set_element", ["id": "lamp_1", "description": "A lamp."])
    #expect(!(await call("send_to_generation", send: .init(status: "Sent", sent: true))).isError)
    #expect(await call("send_to_generation", send: .init(status: "Refused", sent: false)).isError)
  }

  @Test func writingReportsWhatHappened() async {
    #expect(await call("write_with_llm").isError)  // nothing to write from
    state.document.description = "a room"
    let ok = await call("write_with_llm", write: .init(wrote: true, status: "Done"))
    #expect(!ok.isError && object(ok.text)["status"] as? String == "Done")
    #expect(await call("write_with_llm", write: .init(wrote: false, status: "No language model.")).isError)
  }

  @Test func theModelIsTheAssignedOneAndOnlyUsesThatWritePromptsCount() {
    func lm(_ n: String, _ f: String, _ u: String) -> DTHubLanguageModel { DTHubLanguageModel(name: n, path: "/m/\(n)", supportsImages: false, family: f, use: u) }
    let models = [lm("a-plugins", "flux3_5b", "plugins"), lm("b-i2i", "flux3_5b", "i2i"), lm("c-general", "*", "both")]
    #expect(F3ModelChoice.mode(family: "flux3_5b", models: models, readFile: { _ in nil }) == .standard(model: "c-general"))
    #expect(F3ModelChoice.mode(family: "flux3_5b", models: models + [lm("d-t2i", "flux3_5b", "t2i")], readFile: { _ in nil }) == .standard(model: "d-t2i"))
  }
}
