import Foundation
import MCP
import Testing

@testable import HubMCP

@MainActor
struct ReadToolsTests {
  func text(_ r: ToolResult) -> String {
    if case .text(let t)? = r.outputs.first { return t }
    return ""
  }

  @Test func getAppStateIncludesModeBudgetAndActiveJob() async throws {
    let h = Harness(mode: .editFields)
    _ = try h.jobs.begin(kind: .run, images: 2)
    let result = await h.registry.call("get_app_state", arguments: [:])
    #expect(!result.isError)
    let t = text(result)
    #expect(t.contains("\"mode\" : \"editFields\""))
    #expect(t.contains("\"imageLimit\" : 200"))
    #expect(t.contains("job-1"))
  }

  @Test func getPromptGuideForUnknownFamilyIsClearError() async {
    let result = await Harness().registry.call("get_prompt_guide", arguments: ["family": .string("zzz")])
    #expect(result.isError && text(result).contains("zzz"))
  }

  @Test func getPromptGuideReturnsTheGuide() async {
    let result = await Harness().registry.call("get_prompt_guide", arguments: ["family": .string("flux2")])
    #expect(text(result) == "Write long natural prompts.")
  }

  @Test func getImageReturnsImageContent() async {
    let h = Harness()
    h.host.images["r1"] = Data([1, 2, 3])
    let result = await h.registry.call("get_image", arguments: ["result_id": .string("r1")])
    #expect(result.outputs == [.image(Data([1, 2, 3]), mimeType: "image/png")])
  }

  @Test func getImageUnknownResultIDIsClearError() async {
    let result = await Harness().registry.call("get_image", arguments: ["result_id": .string("old")])
    #expect(result.isError && text(result).contains("old"))
  }

  @Test func waitForJobReturnsStatusNotErrorAtTimeout() async throws {
    let h = Harness()
    let id = try h.jobs.begin(kind: .run, images: 1)
    let result = await h.registry.call("wait_for_job", arguments: ["job_id": .string(id), "timeout_seconds": .int(0)])
    #expect(!result.isError && text(result).contains("running"))
  }

  @Test func getResultsFiltersByJob() async throws {
    let h = Harness()
    h.host.resultList = [
      AgentResult(id: "a", path: "/a.png", prompt: "p", model: "m", date: Date(timeIntervalSince1970: 0)),
      AgentResult(id: "b", path: "/b.png", prompt: "p", model: "m", date: Date(timeIntervalSince1970: 0)),
    ]
    let id = try h.jobs.begin(kind: .run, images: 1)
    h.jobs.apply(.finished(resultIDs: ["b"]))
    let t = text(await h.registry.call("get_results", arguments: ["job_id": .string(id)]))
    #expect(t.contains("/b.png") && !t.contains("/a.png"))
  }

  @Test func missingRequiredArgumentIsClearError() async {
    let result = await Harness().registry.call("get_job", arguments: [:])
    #expect(result.isError && text(result).contains("job_id"))
  }
}
