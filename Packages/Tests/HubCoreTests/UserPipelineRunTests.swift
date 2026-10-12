import Foundation
import HubKit
import Testing

@testable import HubCore

struct UserPipelineConversionTests {
  @Test func convertsToARunPipeline() {
    let pipeline = UserPipeline(
      chain: true,
      steps: [
        .init(preset: nil, scale: 3, strength: 0.5), .init(preset: "Q", scale: 2),
        .init(preset: nil, scale: 1.5, strength: 0.4), .init(preset: "R", strength: 0.3),
      ]
    ).pluginPipeline(named: "Mia")
    #expect(pipeline.name == "Mia")
    #expect(pipeline.steps.map(\.preset) == ["", "Q", "", "R"])
    #expect(pipeline.steps.map(\.useOutputAsStart) == [false, true, true, true])
    #expect(pipeline.steps.map(\.scale) == [1, 2, 1.5, 1])
    #expect(pipeline.steps.map(\.strength) == [nil, nil, nil, 0.3])
    #expect(pipeline.steps.map(\.usesPresetModel) == [true, true, true, true])
  }

  @Test func withoutChainNoPassTakesThePreviousOutput() {
    let pipeline = UserPipeline(chain: false, steps: [.init(preset: "A"), .init(preset: "B", scale: 2)])
      .pluginPipeline(named: "X")
    #expect(pipeline.steps.map(\.useOutputAsStart) == [false, false])
    #expect(pipeline.steps.map(\.scale) == [1, 2])
  }
}

@MainActor
struct UserPipelineContributionTests {
  let target = FakeContributionTarget()
  let store = ContributionStore()
  let files = UserPipelineStore(
    folder: FileManager.default.temporaryDirectory.appendingPathComponent("UserPipelineContributionTests-\(UUID())", isDirectory: true))

  init() { store.target = target }

  func plugin(_ passes: Int) -> PluginContribution {
    PluginContribution(pipeline: PluginPipeline(name: "p", steps: Array(repeating: PipelineStep(), count: passes)))
  }

  func user(_ passes: Int) -> UserPipeline {
    UserPipeline(steps: [.init(preset: nil)] + (1..<passes).map { .init(preset: "P\($0)") })
  }

  @Test func theUsersPipelineReplacesAPluginsWithoutAConflict() {
    store.receive(plugin(2), from: "a")
    #expect(store.pipeline?.pluginID == "a" && store.pipeline?.userPipelineName == nil)
    #expect(store.setUserPipeline(user(3).pluginPipeline(named: "Mia"), named: "Mia"))
    #expect(store.pipeline?.userPipelineName == "Mia")
    #expect(store.pipeline?.pluginID == nil)
    #expect(store.pipeline?.pipeline.steps.count == 3)
    #expect(store.conflicts.isEmpty)
  }

  @Test func choosingAUsersPipelineDropsAPendingPipelineConflict() {
    store.receive(plugin(2), from: "a")
    store.receive(plugin(3), from: "b")
    #expect(store.conflicts.count == 1)
    store.setUserPipeline(user(2).pluginPipeline(named: "Mia"), named: "Mia")
    #expect(store.conflicts.isEmpty)
  }

  @Test func aPluginReplacesTheUsersIdlePipelineWithoutAConflict() {
    store.setUserPipeline(user(2).pluginPipeline(named: "Mia"), named: "Mia")
    #expect(store.receive(plugin(4), from: "a").isEmpty)
    #expect(store.pipeline?.pluginID == "a")
    #expect(store.conflicts.isEmpty)
  }

  @Test func forgettingAPluginKeepsTheUsersPipeline() {
    store.setUserPipeline(user(2).pluginPipeline(named: "Mia"), named: "Mia")
    store.forget("a")
    #expect(store.pipeline?.userPipelineName == "Mia")
  }

  /// While a pipeline runs no pipeline can be sent to RUN: a plug-in's is refused, the user's is not taken.
  @Test func whileAPipelineRunsNoPipelineIsTaken() {
    store.setUserPipeline(user(2).pluginPipeline(named: "Mia"), named: "Mia")
    store.pipelineLocked = true
    let problems = store.receive(plugin(4), from: "a")
    #expect(problems.count == 1 && problems[0].hasPrefix("pipeline:"))
    #expect(store.pipeline?.userPipelineName == "Mia" && store.conflicts.isEmpty)
    #expect(store.setUserPipeline(user(3).pluginPipeline(named: "Altra"), named: "Altra") == false)
    #expect(store.pipeline?.userPipelineName == "Mia")
    store.pipelineLocked = false
    #expect(store.receive(plugin(4), from: "a").isEmpty)
    #expect(store.pipeline?.pluginID == "a")
  }

  @Test func whileAPipelineRunsAPluginsFieldsStillArrive() {
    store.pipelineLocked = true
    var contribution = plugin(2)
    contribution.fields = FieldOverlay([.steps: .int(24)])
    store.receive(contribution, from: "a")
    #expect(target.fields.parameters.steps == 24)
    #expect(store.pipeline == nil)
  }

  @Test func syncingFollowsARenamedFile() throws {
    try files.save(user(2), named: "Mia")
    store.setUserPipeline(user(2).pluginPipeline(named: "Mia"), named: "Mia")
    try files.rename("Mia", to: "Tua")
    store.syncUserPipeline(with: files, renamedTo: "Tua")
    #expect(store.pipeline?.userPipelineName == "Tua")
    #expect(store.pipeline?.pipeline.name == "Tua")
  }

  @Test func syncingReloadsAChangedFile() throws {
    try files.save(user(2), named: "Mia")
    store.setUserPipeline(user(2).pluginPipeline(named: "Mia"), named: "Mia")
    try files.save(user(3), named: "mia")
    store.syncUserPipeline(with: files)
    #expect(store.pipeline?.userPipelineName == "Mia")
    #expect(store.pipeline?.pipeline.steps.count == 3)
  }

  @Test func syncingRemovesADeletedPipeline() throws {
    try files.save(user(2), named: "Mia")
    store.setUserPipeline(user(2).pluginPipeline(named: "Mia"), named: "Mia")
    files.delete(named: "Mia")
    store.syncUserPipeline(with: files)
    #expect(store.pipeline == nil)
  }

  @Test func syncingLeavesAPluginsPipelineAlone() {
    store.receive(plugin(2), from: "a")
    store.syncUserPipeline(with: files)
    #expect(store.pipeline?.pluginID == "a")
  }
}
