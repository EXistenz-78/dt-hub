import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterI4

@MainActor
@Suite("The MCP tools")
struct ToolsTests {
  let state: I4State

  init() {
    state = I4State(
      data: I4Data(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig, warnings: []),
      store: I4Store(storage: MemoryStorage()), italian: false)
    state.active = true
    state.update(models: [], family: "ideogram_4")
  }

  private func lm(_ name: String, family: String?, use: String) -> DTHubLanguageModel {
    DTHubLanguageModel(name: name, path: "/m/\(name)", supportsImages: false, family: family, use: use)
  }

  func call(_ tool: String, _ arguments: [String: Any] = [:], write: I4Writer.Outcome? = nil, send: PromptSender.Outcome? = nil) async -> (text: String, isError: Bool) {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let answer = await I4Tools.handle(call, state: state, actions: .init(write: { write }, send: { send }))
    let object = try! JSONSerialization.jsonObject(with: answer) as! [String: Any]
    return (object["text"] as? String ?? "", object["isError"] as? Bool ?? false)
  }

  func object(_ text: String) -> [String: Any] {
    let body = text.drop { $0 != "{" }
    return (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
  }

  @Test func theDeclarationsAreWellFormedAndNoneStartsAGeneration() throws {
    for tool in I4Tools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20 && tool.level != .generate)
    }
    #expect(I4Tools.declarations.filter { $0.level == .read }.map(\.name) == ["get_status", "search_terms"])
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(I4Tools.declarations)) is [[String: Any]])
    #expect(PromptMasterI4Plugin().manifest.tools?.map(\.name) == I4Tools.declarations.map(\.name))
  }

  @Test func theModelWrittenWithIsTheOneAssignedToTheFamily() {
    #expect(state.writeModel == nil)
    state.update(models: [lm("general", family: "*", use: "both")], family: "ideogram_4")
    #expect(state.writeModel == nil)
    state.update(models: [lm("general", family: "*", use: "both"), lm("ideo", family: "ideogram_4", use: "enhance"), lm("cap", family: "ideogram_4", use: "describe")], family: "ideogram_4")
    #expect(state.writeModel == "ideo")
  }

  @Test func searchSetBriefAndElementsChangeTheTab() async throws {
    let found = object(await call("search_terms", ["limit": 3]).text)
    let terms = try #require(found["terms"] as? [[String: Any]])
    let id = try #require(terms.first?["id"] as? String)
    let set = await call("set_brief", ["description": "a harbour", "add_terms": id, "background": "fog"])
    #expect(!set.isError && state.document.description == "a harbour" && state.isChosen(id) && state.document.background == "fog")
    _ = await call("set_brief", ["remove_terms": id])
    #expect(!state.isChosen(id))
    let added = object(await call("add_element", ["type": "text", "description": "a sign", "text": "OPEN", "y0": 100, "x0": 100, "y1": 300, "x1": 400]).text)
    #expect(added["id"] as? Int == 1 && state.document.elements.first?.text == "OPEN" && state.document.elements.first?.bbox != nil)
    let status = object(await call("get_status").text)
    #expect((status["elements"] as? [[String: Any]])?.count == 1 && status["canWrite"] as? Bool == true)
    #expect(!(await call("remove_element", ["id": 1])).isError && state.document.elements.isEmpty)
  }

  @Test func badInputIsRefusedAndChangesNothing() async {
    state.document.description = "keep"
    #expect(await call("set_brief", ["description": "new", "add_terms": "nope"]).isError && state.document.description == "keep")
    #expect(await call("set_brief", ["mode": "sepia"]).isError)
    #expect(await call("add_element", ["y0": 1, "x0": 1]).isError)
    #expect(await call("add_element", ["y0": 10, "x0": 10, "y1": 12, "x1": 12]).isError)
    #expect(await call("add_element", ["type": "blob"]).isError)
    #expect(await call("remove_element", ["id": 99]).isError && state.document.elements.isEmpty)
  }

  @Test func writingAndSendingNeedWhatTheButtonsNeed() async {
    #expect(await call("write_with_llm").isError)  // nothing to write
    state.document.description = "a harbour"
    let ok = I4Writer.Outcome(phrases: ["description": WrittenPhrase(text: "A harbour.", input: "x")], failed: [], status: "Done")
    let written = object(await call("write_with_llm", write: ok).text)
    #expect(written["written"] as? Int == 1)
    #expect(await call("write_with_llm", write: I4Writer.Outcome(status: "No language model is chosen.")).isError)
    let sent = await call("send_to_generation", send: PromptSender.Outcome(status: "Sent", sent: true))
    #expect(!sent.isError)
    #expect(await call("send_to_generation", send: PromptSender.Outcome(status: "Refused", sent: false)).isError)
    state.active = false
    #expect(await call("send_to_generation", send: PromptSender.Outcome(status: "Sent", sent: true)).isError)
  }
}
