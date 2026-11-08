import Foundation
import MCP
import Testing

@testable import HubMCP

@MainActor
struct ControlToolsTests {
  func harness(budget: Int = 200, threshold: Int = 20, images: Int = 1) -> Harness {
    let h = Harness(mode: .full)
    h.settings.value.imageBudget = budget
    h.settings.value.confirmThreshold = threshold
    h.host.plan = AgentRunPlan(images: images, summary: "\(images) images with FLUX.2 klein")
    return h
  }

  func text(_ r: ToolResult) -> String {
    if case .text(let t)? = r.outputs.first { return t }
    return ""
  }

  @Test func runStartsJobAndReturnsJobIDImmediately() async {
    let h = harness(images: 2)
    let r = await h.registry.call("run", arguments: [:])
    #expect(!r.isError && text(r).contains("job-1"))
    #expect(h.host.calls == ["startRun"])
    #expect(h.jobs.activeJobID == "job-1")
    #expect(h.ledger.usedImages == 2)
  }

  @Test func runWhileJobActiveReturnsBusyWithJobID() async {
    let h = harness()
    _ = await h.registry.call("run", arguments: [:])
    let r = await h.registry.call("run", arguments: [:])
    #expect(r.isError && text(r).contains("job-1"))
    #expect(h.host.calls == ["startRun"])
    #expect(h.ledger.usedImages == 1)
  }

  @Test func runWhileUserStartedRunByHandReturnsBusyAndRefunds() async {
    let h = harness(images: 3)
    h.host.startError = .busy(jobID: nil)
    let r = await h.registry.call("run", arguments: [:])
    #expect(r.isError && text(r).contains("already running"))
    #expect(h.ledger.usedImages == 0)
    #expect(h.jobs.activeJobID == nil)
  }

  @Test func setModelWhileJobActiveIsRefused() async {
    let h = harness()
    _ = await h.registry.call("run", arguments: [:])
    let r = await h.registry.call("set_model", arguments: ["file": .string("flux2.ckpt")])
    #expect(r.isError && text(r).contains("job-1"))
    #expect(!h.host.calls.contains("setModel flux2.ckpt"))
  }

  @Test func setModelRefusesUnknownFileAndNotifiesListChange() async {
    let h = harness()
    #expect(await h.registry.call("set_model", arguments: ["file": .string("nope.ckpt")]).isError)
    var fired = 0
    h.context.onHostChanged = { fired += 1 }
    #expect(await h.registry.call("set_model", arguments: ["file": .string("flux2.ckpt")]).isError == false)
    #expect(h.host.calls == ["setModel flux2.ckpt"] && fired == 1)
  }

  @Test func runBeyondBudgetFailsImmediatelyWithUsedAndLimit() async {
    let h = harness(budget: 5, images: 6)
    h.ledger.confirm()
    let r = await h.registry.call("run", arguments: [:])
    #expect(r.isError && text(r).contains("0 of 5"))
    #expect(h.host.calls.isEmpty && h.jobs.activeJobID == nil)
  }

  @Test func runAboveThresholdWithUnconfirmedBudgetAsksOnce() async {
    let h = harness(threshold: 20, images: 30)
    let r = await h.registry.call("run", arguments: [:])
    #expect(!r.isError)
    #expect(h.prompter.asked == ["30 images with FLUX.2 klein"])
  }

  @Test func refusedConfirmationDoesNotStartAnything() async {
    let h = harness(threshold: 20, images: 30)
    h.prompter.answer = false
    let r = await h.registry.call("run", arguments: [:])
    #expect(r.isError)
    #expect(h.host.calls.isEmpty && h.ledger.usedImages == 0 && h.jobs.activeJobID == nil)
  }

  @Test func definePipelineRejects21StepsAndAccepts20() async {
    let h = harness()
    func steps(_ n: Int) -> Value { .array((0..<n).map { _ in .object(["prompt": .string("p")]) }) }
    #expect(await h.registry.call("define_pipeline", arguments: ["steps": steps(21)]).isError)
    #expect(await h.registry.call("define_pipeline", arguments: ["steps": steps(20)]).isError == false)
    #expect(h.host.calls == ["definePipeline 20"])
  }

  @Test func queueRemoveRefusesEntriesNotAddedByAgent() async throws {
    let h = harness()
    let foreign = UUID()
    h.host.queue = [AgentQueueEntry(id: foreign, summary: "user's", status: "pending")]
    let refused = await h.registry.call("queue_remove", arguments: ["id": .string(foreign.uuidString)])
    #expect(refused.isError && h.host.queue.count == 1)
    let added = await h.registry.call("queue_add", arguments: [:])
    let id = text(added).components(separatedBy: CharacterSet(charactersIn: " \n\"")).first { UUID(uuidString: $0) != nil }
    let ok = await h.registry.call("queue_remove", arguments: ["id": .string(try #require(id))])
    #expect(!ok.isError)
  }

  @Test func twoConcurrentRunCallsOnlyOneStarts() async {
    let h = harness()
    async let a = h.registry.call("run", arguments: [:])
    async let b = h.registry.call("run", arguments: [:])
    let results = await [a, b]
    #expect(results.filter { !$0.isError }.count == 1)
    #expect(h.host.calls.filter { $0 == "startRun" }.count == 1)
  }

  @Test func stopCallsHostAndMarksJobStopped() async {
    let h = harness()
    _ = await h.registry.call("run", arguments: [:])
    _ = await h.registry.call("stop", arguments: [:])
    #expect(h.host.calls.contains("stop"))
    #expect(h.jobs.status("job-1")?.state == .stopped)
  }

  @Test func queueStartUsesQueuePlanAndBudget() async {
    let h = harness(images: 8)
    let r = await h.registry.call("queue_start", arguments: [:])
    #expect(!r.isError && h.host.calls == ["startQueue"] && h.ledger.usedImages == 8)
    #expect(h.jobs.status("job-1")?.kind == .queue)
  }

  @Test func runPipelineStartsNamedPipeline() async {
    let h = harness(images: 4)
    let r = await h.registry.call("run_pipeline", arguments: ["name": .string("Upscale chain")])
    #expect(!r.isError && h.host.calls == ["startPipeline Upscale chain"])
    #expect(h.jobs.status("job-1")?.kind == .pipeline)
  }

  @Test func specialistToolsAreControlToolsShownOnlyWithSpecialist() async {
    let h = harness()
    #expect(!h.registry.visibleTools().contains { $0.name == "enhance_prompt" })
    h.host.hasSpecialistLLM = true
    #expect(h.registry.visibleTools().contains { $0.name == "enhance_prompt" })
    #expect(text(await h.registry.call("enhance_prompt", arguments: [:])) == "enhanced")
  }
}
