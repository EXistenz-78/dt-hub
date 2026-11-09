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

  @Test func queueAddWhileAgentQueueRunsIsRefused() async {
    let h = harness(images: 3)
    _ = await h.registry.call("queue_start", arguments: [:])
    let r = await h.registry.call("queue_add", arguments: [:])
    #expect(r.isError && text(r).contains("job-1"))
    #expect(h.host.queue.isEmpty)
  }

  @Test func queueAddWhileUserQueueRunsIsRefused() async {
    let h = harness()
    h.host.queueRunning = true
    #expect(await h.registry.call("queue_add", arguments: [:]).isError)
  }

  @Test func queueAddDuringAPlainRunIsAllowed() async {
    let h = harness()
    _ = await h.registry.call("run", arguments: [:])
    #expect(await h.registry.call("queue_add", arguments: [:]).isError == false)
  }

  @Test func confirmationAnsweredAfterDisconnectDoesNotStart() async {
    let h = harness(threshold: 20, images: 30)
    h.prompter.onAsk = { h.jobs.clientDisconnected() }
    let r = await h.registry.call("run", arguments: [:])
    #expect(r.isError)
    #expect(h.host.calls.isEmpty && h.ledger.usedImages == 0 && h.jobs.activeJobID == nil)
  }

  @Test func runAsksNothingWhenTheAppIsAlreadyGenerating() async {
    let h = harness(threshold: 20, images: 30)
    h.host.stateValue.isGenerating = true
    let r = await h.registry.call("run", arguments: [:])
    #expect(r.isError && text(r).contains("already running"))
    #expect(h.prompter.asked.isEmpty && h.jobs.activeJobID == nil)
  }

  @Test func runRefusesWhileAPipelineIsSelectedAndSaysHow() async {
    let h = harness()
    h.host.stateValue.selectedPipeline = "Agent pipeline"
    let r = await h.registry.call("run", arguments: [:])
    #expect(r.isError && text(r).contains("Agent pipeline") && text(r).contains("clear_pipeline"))
    #expect(h.host.calls.isEmpty && h.jobs.activeJobID == nil && h.ledger.usedImages == 0)
  }

  @Test func clearPipelineIsAnEditToolAndForwardsToTheHost() async {
    let edit = Set(Harness(mode: .editFields).registry.visibleTools().map(\.name))
    #expect(edit.contains("clear_pipeline"))
    let h = harness()
    #expect(await h.registry.call("clear_pipeline", arguments: [:]).isError == false)
    #expect(h.host.calls == ["clearPipeline"])
  }

  @Test func selectPipelineAndRecallAreEditToolsAndForwardToTheHost() async {
    let edit = Set(Harness(mode: .editFields).registry.visibleTools().map(\.name))
    #expect(edit.contains("select_pipeline") && edit.contains("recall_from_result"))
    let h = harness()
    #expect(await h.registry.call("select_pipeline", arguments: ["name": .string("Hero")]).isError == false)
    #expect(await h.registry.call("select_pipeline", arguments: ["name": .string("Nope")]).isError)
    #expect(await h.registry.call("recall_from_result", arguments: ["result_id": .string("r1"), "prompt": .bool(false)]).isError == false)
    #expect(await h.registry.call("recall_from_result", arguments: ["result_id": .string("r1"), "prompt": .bool(false), "parameters": .bool(false)]).isError)
    #expect(h.host.calls == ["selectPipeline Hero", "recallResult r1 false true"])
  }

  @Test func setModelWarnsAboutLoRAsOfAnotherFamily() async {
    let h = harness()
    h.host.currentFamily = "flux3_5b"
    h.host.stateValue.loras = [AgentLoRAUse(file: "k.ckpt", weight: 1), AgentLoRAUse(file: "f.ckpt", weight: 1)]
    h.host.loraList = [
      AgentLoRA(file: "k.ckpt", name: "Krea", families: ["krea_2"]), AgentLoRA(file: "f.ckpt", name: "Flux3", families: ["flux3_5b"]),
    ]
    let r = await h.registry.call("set_model", arguments: ["file": .string("flux2.ckpt")])
    #expect(!r.isError)
    #expect(text(r).contains("k.ckpt") && text(r).contains("remove_lora") && !text(r).contains("f.ckpt"))
  }

  @Test func setModelSaysNothingAboutLoRAsThatFit() async {
    let h = harness()
    #expect(text(await h.registry.call("set_model", arguments: ["file": .string("flux2.ckpt")])) == "Model set to flux2.ckpt.")
  }

  @Test func serverStatusIsAReadToolAvailableInReadOnlyMode() async {
    let h = Harness(mode: .readOnly)
    let r = await h.registry.call("get_server_status", arguments: [:])
    #expect(!r.isError && text(r).contains("\"mode\" : \"managed\"") && text(r).contains("\"canSwitch\" : true"))
  }

  @Test func switchServerIsAControlToolHiddenBelowFullMode() {
    #expect(!Set(Harness(mode: .editFields).registry.visibleTools().map(\.name)).contains("switch_server"))
    #expect(Set(harness().registry.visibleTools().map(\.name)).contains("switch_server"))
  }

  @Test func switchServerForwardsToTheHostAndReturnsTheNewStatus() async {
    let h = harness()
    var fired = 0
    h.context.onHostChanged = { fired += 1 }
    let r = await h.registry.call("switch_server", arguments: [:])
    #expect(!r.isError && text(r).contains("\"mode\" : \"attach\""))
    #expect(h.host.calls == ["switchServer"] && fired == 1)
  }

  @Test func switchServerIsRefusedWhileAJobRuns() async {
    let h = harness()
    _ = await h.registry.call("run", arguments: [:])
    let r = await h.registry.call("switch_server", arguments: [:])
    #expect(r.isError && text(r).contains("job-1") && text(r).contains("stop"))
    #expect(!h.host.calls.contains("switchServer"))
  }

  @Test func switchServerSaysWhyItCannotSwitch() async {
    let h = harness()
    h.host.server.canSwitch = false
    h.host.server.cannotSwitchReason = "The other server's settings are not valid."
    let r = await h.registry.call("switch_server", arguments: [:])
    #expect(r.isError && text(r).contains("settings are not valid"))
  }

  @Test func listProjectsIsAReadTool() async {
    let r = await Harness(mode: .readOnly).registry.call("list_projects", arguments: [:])
    #expect(!r.isError && text(r).contains("Test vari") && text(r).contains("Altro"))
  }

  @Test func projectToolsAreControlToolsHiddenBelowFullMode() {
    let edit = Set(Harness(mode: .editFields).registry.visibleTools().map(\.name))
    #expect(!edit.contains("open_project") && !edit.contains("create_project"))
    let full = Set(harness().registry.visibleTools().map(\.name))
    #expect(full.contains("open_project") && full.contains("create_project"))
  }

  @Test func openProjectForwardsAndRefusesUnknownNames() async {
    let h = harness()
    #expect(await h.registry.call("open_project", arguments: ["name": .string("Altro")]).isError == false)
    let r = await h.registry.call("open_project", arguments: ["name": .string("Zzz")])
    #expect(r.isError && text(r).contains("Zzz"))
    #expect(h.host.calls == ["openProject Altro"])
  }

  @Test func openProjectIsRefusedWhileAJobRunsAndTellsHowToProceed() async {
    let h = harness()
    _ = await h.registry.call("run", arguments: [:])
    let r = await h.registry.call("open_project", arguments: ["name": .string("Altro")])
    #expect(r.isError && text(r).contains("job-1") && text(r).contains("stop"))
    #expect(!h.host.calls.contains("openProject Altro"))
  }

  @Test func createProjectForwardsTheName() async {
    let h = harness()
    #expect(await h.registry.call("create_project", arguments: ["name": .string("Frutta")]).isError == false)
    #expect(h.host.calls == ["createProject Frutta"])
  }

  @Test func openProjectForgetsTheQueueEntriesOfTheOldProject() async {
    let h = harness()
    let added = await h.registry.call("queue_add", arguments: [:])
    let id = text(added)
    _ = await h.registry.call("open_project", arguments: ["name": .string("Altro")])
    #expect(await h.registry.call("queue_remove", arguments: ["id": .string(id)]).isError)
  }
}
