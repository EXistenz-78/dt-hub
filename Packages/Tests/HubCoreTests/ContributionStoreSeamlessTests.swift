import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct ContributionStoreSeamlessTests {
  let target = FakeContributionTarget()
  let store = ContributionStore()
  let steps = [PipelineStep(title: "a")]

  init() { store.target = target }

  private func pipeline(_ name: String, seamless: SeamlessTile? = nil) -> PluginPipeline {
    PluginPipeline(name: name, steps: [PipelineStep(title: name, seamless: seamless)])
  }

  private let withdrawal = PluginContribution(withdrawsPipeline: true)

  @Test func aPluginWithdrawsOnlyItsOwnPipeline() {
    store.receive(PluginContribution(pipeline: pipeline("A")), from: "a")
    #expect(store.pipeline?.pluginID == "a")
    // B withdraws: A's stays.
    store.receive(withdrawal, from: "b")
    #expect(store.pipeline?.pluginID == "a")
    // A withdraws: gone.
    store.receive(withdrawal, from: "a")
    #expect(store.pipeline == nil)
    // The user's own pipeline is never touched by a plug-in.
    #expect(store.setUserPipeline(pipeline("mine"), named: "mine"))
    store.receive(withdrawal, from: "a")
    #expect(store.pipeline?.userPipelineName == "mine")
  }

  @Test func withdrawingWhileAPipelineRunsChangesNothing() {
    store.receive(PluginContribution(pipeline: pipeline("A")), from: "a")
    store.pipelineLocked = true
    let problems = store.receive(withdrawal, from: "a")
    #expect(problems == ["pipeline: a pipeline is running."])
    #expect(store.pipeline?.pluginID == "a")
  }

  @Test func aSeamlessStepIsRefusedWithoutTheCustomServer() {
    store.seamlessProblem = { SeamlessTile.problem(customServer: false, family: $0) }
    store.receive(PluginContribution(pipeline: pipeline("Other")), from: "b")
    let problems = store.receive(
      PluginContribution(pipeline: pipeline("S", seamless: .both)), from: "a", family: "krea_2")
    #expect(problems == ["seamless: the custom server is not running."])
    #expect(store.pipeline?.pluginID == "b")
    #expect(store.conflicts.isEmpty)
  }

  @Test func aSeamlessStepIsRefusedOnAnotherFamily() {
    store.seamlessProblem = { SeamlessTile.problem(customServer: true, family: $0) }
    let problems = store.receive(
      PluginContribution(pipeline: pipeline("S", seamless: .both)), from: "a", family: "sdxl")
    #expect(problems == ["seamless: this model family does not support it."])
    #expect(store.pipeline == nil)
  }

  @Test func aSeamlessStepIsAcceptedOnAFittingFamilyAndAGuidedEstimateIsChecked() {
    store.seamlessProblem = { SeamlessTile.problem(customServer: true, family: $0) }
    let problems = store.receive(
      PluginContribution(pipeline: pipeline("S", seamless: .upDown)), from: "a", family: "z_image")
    #expect(problems.isEmpty)
    #expect(store.pipeline?.pluginID == "a")
    let guided = PluginPipeline(
      name: "G", steps: [], guided: GuidedPipeline(passes: 2, estimate: PipelineStep(seamless: .both)))
    let refused = store.receive(PluginContribution(pipeline: guided), from: "a", family: "sdxl")
    #expect(refused == ["seamless: this model family does not support it."])
    #expect(store.pipeline?.pipeline.guided == nil)
  }

  @Test func aStepWithoutSeamlessIsNeverChecked() {
    store.seamlessProblem = { _ in "never" }
    let problems = store.receive(PluginContribution(pipeline: pipeline("plain")), from: "a", family: "sdxl")
    #expect(problems.isEmpty)
    #expect(store.pipeline?.pluginID == "a")
  }

  @Test func turningThePluginOffDropsItsSeamlessPipeline() {
    store.seamlessProblem = { SeamlessTile.problem(customServer: true, family: $0) }
    store.receive(PluginContribution(pipeline: pipeline("S", seamless: .both)), from: "a", family: "krea_2")
    #expect(store.pipeline?.pluginID == "a")
    store.forget("a")
    #expect(store.pipeline == nil)
  }
}
