import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct ContributionStoreGuidedTests {
  let target = FakeContributionTarget()
  let store = ContributionStore()

  init() { store.target = target }

  private func guided(_ passes: Int) -> PluginPipeline {
    PluginPipeline(name: "g", steps: [], guided: GuidedPipeline(passes: passes))
  }

  @Test func holdsAGuidedPipelineAndCountsItsPasses() {
    store.receive(PluginContribution(pipeline: guided(12)), from: "a")
    #expect(store.pipeline?.pipeline.passCount == 12)
    #expect(store.pipeline?.pipeline.guided != nil)
  }

  @Test func aConflictShowsTheGuidedPassCount() {
    store.receive(PluginContribution(pipeline: guided(12)), from: "a")
    store.receive(
      PluginContribution(pipeline: PluginPipeline(name: "p", steps: [PipelineStep(), PipelineStep()])), from: "b")
    let conflict = store.conflicts.first { $0.subject == .pipeline }
    #expect(conflict?.current.content == .passes(12))
    #expect(conflict?.proposed.content == .passes(2))
  }

  @Test func aResultGoesToTheTargetWithItsDescription() {
    let result = PluginResult(image: PluginImageRef(name: "r", path: "/t/r.png"), description: "Tiled Upscale 2×")
    let problems = store.receive(PluginContribution(result: result), from: "a")
    #expect(problems.isEmpty)
    #expect(target.results.map(\.description) == ["Tiled Upscale 2×"])
    #expect(target.results.first?.image.path == "/t/r.png")
  }

  @Test func aResultThatCannotBeAddedIsAProblemNotACrash() {
    target.resultFails = true
    let result = PluginResult(image: PluginImageRef(name: "r", path: "/t/r.png"), description: "")
    let problems = store.receive(PluginContribution(result: result), from: "a")
    #expect(problems.count == 1 && problems[0].hasPrefix("r"))
  }

  @Test func aGuidedPipelineIsConsumedWhenItsRunEnds() {
    store.receive(PluginContribution(pipeline: guided(9)), from: "a")
    store.finishedGuidedPipeline()
    #expect(store.pipeline == nil, "its session is gone: running it again would be empty")
  }

  @Test func aStaticPipelineStaysAfterARun() {
    store.receive(PluginContribution(pipeline: PluginPipeline(name: "p", steps: [PipelineStep()])), from: "a")
    store.finishedGuidedPipeline()
    #expect(store.pipeline != nil, "only a guided one is consumed")
  }
}
