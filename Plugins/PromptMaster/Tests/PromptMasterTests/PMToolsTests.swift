import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMaster

@MainActor
@Suite("The MCP tools")
struct PMToolsTests {
  let state: PMState
  var written: [String] = []

  init() {
    state = PMState(
      store: PMStore(defaults: UserDefaults(suiteName: "pm-tools-\(UUID().uuidString)")!),
      customStore: CustomTermsStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("pm-tools-\(UUID().uuidString)")),
      italian: false)
    state.update(family: "flux2_9b", guide: PMStateTests.guide("flux2_9b"), languageModels: [])
    state.active = true
  }

  private func lm(_ name: String, family: String?, use: String) -> DTHubLanguageModel {
    let f = family.map { #","family":"\#($0)""# } ?? ""
    return try! JSONDecoder().decode(
      DTHubLanguageModel.self, from: Data(#"{"name":"\#(name)","path":"/m/\#(name)","supportsImages":false\#(f),"use":"\#(use)"}"#.utf8))
  }

  func call(
    _ tool: String, _ arguments: [String: Any] = [:], write: PMWriter.Outcome? = nil, ratio: PMWriter.Outcome? = nil
  ) async -> (text: String, isError: Bool) {
    let body: [String: Any] = ["type": "tool.call", "tool": tool, "arguments": arguments]
    let call = DTHubToolCall(try! JSONSerialization.data(withJSONObject: body))!
    let actions = PMTools.Actions(write: { write }, applyRatio: { ratio })
    let answer = await PMTools.handle(call, state: state, actions: actions)
    let object = try! JSONSerialization.jsonObject(with: answer) as! [String: Any]
    return (object["text"] as? String ?? "", object["isError"] as? Bool ?? false)
  }

  func object(_ text: String) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:] }

  @Test func theDeclarationsAreWellFormedAndNoneStartsAGeneration() throws {
    for tool in PMTools.declarations {
      #expect(tool.name.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil)
      #expect(tool.description.count > 20)
      #expect(tool.level != .generate)
    }
    #expect(PMTools.declarations.map(\.name) == ["get_status", "search_terms", "set_brief", "list_recipes", "save_recipe", "load_recipe", "delete_recipe", "write_prompt", "apply_suggested_format"])
    #expect(PMTools.declarations.filter { $0.level == .read }.map(\.name) == ["get_status", "search_terms", "list_recipes"])
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(PMTools.declarations)) is [[String: Any]])
    #expect(PMTools.declarations.first { $0.name == "write_prompt" }?.timeout == 600)
  }

  @Test func theManifestListsTheTools() {
    #expect(PromptMasterPlugin().manifest.tools?.map(\.name) == PMTools.declarations.map(\.name))
  }

  @Test func statusSaysWhatTheTabHoldsAndWhyItCannotWrite() async {
    let answer = await call("get_status")
    let status = object(answer.text)
    #expect(!answer.isError && status["family"] as? String == "flux2_9b" && status["canWrite"] as? Bool == false)
    #expect((status["cannotWriteBecause"] as? String)?.contains("Nothing to write from") == true)
    #expect((status["languageModel"] as? [String: Any])?["kind"] as? String == "app_default")
  }

  @Test func statusShowsTheModelAssignedToTheFamily() async {
    state.update(family: "qwen_image_2.1", guide: PMStateTests.guide("qwen_image_2.1"), languageModels: [lm("qwen-writer", family: "qwen_image_2.1", use: "enhance")])
    let model = object(await call("get_status").text)["languageModel"] as? [String: Any]
    #expect(model?["kind"] as? String == "assigned_to_family" && model?["model"] as? String == "qwen-writer")
  }

  @Test func searchFindsTermsAndSetBriefChoosesThem() async throws {
    let found = object(await call("search_terms", ["query": "close-up", "limit": 5]).text)
    let terms = try #require(found["terms"] as? [[String: Any]])
    #expect(!terms.isEmpty && terms.count <= 5 && terms.contains { $0["id"] as? String == "fr_closeup" })
    let set = await call("set_brief", ["description": "a harbour at dawn", "add_terms": "fr_closeup, lq_soft", "mode": "art"])
    #expect(!set.isError && state.description == "a harbour at dawn" && state.mode == .art)
    #expect(state.selection == ["fr_closeup", "lq_soft"])
    _ = await call("set_brief", ["remove_terms": "fr_closeup"])
    #expect(state.selection == ["lq_soft"])
    _ = await call("set_brief", ["clear_terms": true, "add_terms": "fr_closeup"])
    #expect(state.selection == ["fr_closeup"])
  }

  @Test func setBriefRefusesBadInputAndChangesNothing() async {
    state.description = "keep"
    let unknown = await call("set_brief", ["description": "new", "add_terms": "fr_closeup,nope_id"])
    #expect(unknown.isError && unknown.text.contains("nope_id") && state.description == "keep" && state.selection.isEmpty)
    #expect(await call("set_brief", ["mode": "sepia"]).isError)
    #expect(await call("set_brief", ["booru": true]).isError)
    #expect(await call("set_brief", ["description": String(repeating: "a", count: PMTools.maxDescription + 1)]).isError)
  }

  @Test func writingNeedsABriefAndAnActiveTabAndReturnsThePromptWritten() async {
    let ok = PMWriter.Outcome(status: "Prompt sent to Generation.", ratio: "3:2", sent: true, prompt: "A quiet harbour.", negativePrompt: nil)
    #expect(await call("write_prompt", write: ok).isError)  // nothing to write from
    let written = await call("write_prompt", ["description": "a harbour"], write: ok)
    let result = object(written.text)
    #expect(!written.isError && result["prompt"] as? String == "A quiet harbour." && result["suggestedFormat"] as? String == "3:2")
    state.active = false
    let off = await call("write_prompt", write: ok)
    #expect(off.isError && off.text.contains("not active"))
  }

  @Test func aFailedWriteIsAnErrorWithTheReason() async {
    let bad = PMWriter.Outcome(status: "No language model is chosen.", ratio: nil, sent: false)
    state.description = "x"
    let answer = await call("write_prompt", write: bad)
    #expect(answer.isError && answer.text.contains("No language model"))
  }

  @Test func theSuggestedFormatIsAppliedOnlyWhenThereIsOne() async {
    #expect(await call("apply_suggested_format").isError)
    state.suggestedRatio = "16:9"
    let ok = PMWriter.Outcome(status: "Format applied.", ratio: nil, sent: true)
    #expect(!(await call("apply_suggested_format", ratio: ok)).isError)
  }

  @Test func anUnknownToolIsUnsupported() async {
    let call = DTHubToolCall(Data(#"{"type":"tool.call","tool":"nope"}"#.utf8))!
    let answer = await PMTools.handle(call, state: state, actions: .init(write: { nil }, applyRatio: { nil }))
    #expect(String(decoding: answer, as: UTF8.self).contains("unsupported"))
  }
}
