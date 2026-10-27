import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct ContributionStorePipelineTests {
  let steps = [PipelineStep(title: "a", preset: "p")]

  @Test func setPipelineSetsAPluginPipeline() {
    let store = ContributionStore()
    #expect(store.setPipeline(PluginPipeline(name: "Sphere Light", steps: steps), pluginID: "sphere"))
    #expect(store.pipeline?.pluginID == "sphere")
    #expect(store.pipeline?.pipeline.steps == steps)
  }

  @Test func setPipelineRefusesWhileLocked() {
    let store = ContributionStore()
    store.pipelineLocked = true
    #expect(!store.setPipeline(PluginPipeline(steps: steps), pluginID: "sphere"))
    #expect(store.pipeline == nil)
  }

  @Test func setPipelineRefusesAGuidedPipeline() {
    let store = ContributionStore()
    let guided = PluginPipeline(name: "Tiled", steps: [], guided: GuidedPipeline(passes: 3))
    #expect(!store.setPipeline(guided, pluginID: "tiled"))
    #expect(store.pipeline == nil)
  }
}
