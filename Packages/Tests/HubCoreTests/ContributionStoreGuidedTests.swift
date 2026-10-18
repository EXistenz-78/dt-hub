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
}
