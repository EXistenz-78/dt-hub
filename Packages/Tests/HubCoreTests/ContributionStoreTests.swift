import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
final class FakeContributionTarget: ContributionTarget {
  var fields = GenerationFields()
  private(set) var loras: [LoRASelection] = []
  private(set) var moodboard: [UUID: String] = [:]
  private(set) var startImageName: String?
  private(set) var startID: UUID?
  var failImages = false

  var loraFiles: Set<String> { Set(loras.map(\.file)) }
  var moodboardIDs: Set<UUID> { Set(moodboard.keys) }
  var startImageID: UUID? { startID }

  func addLoRA(_ lora: LoRASelection) {
    if let index = loras.firstIndex(where: { $0.file == lora.file }) { loras[index] = lora } else { loras.append(lora) }
  }

  func addMoodboardImage(_ image: PluginImageRef, from pluginID: String) throws -> UUID {
    struct Failure: Error {}
    if failImages { throw Failure() }
    let id = UUID()
    moodboard[id] = image.name
    return id
  }

  func removeMoodboardImage(_ id: UUID) { moodboard[id] = nil }

  func setStartImage(_ image: PluginImageRef, from pluginID: String) throws -> UUID {
    let id = UUID()
    startID = id
    startImageName = image.name
    return id
  }

  func userRemovesStartImage() { startID = nil }
  func userRemovesLoRA(_ file: String) { loras.removeAll { $0.file == file } }
}

@MainActor
struct ContributionStoreTests {
  let target = FakeContributionTarget()
  let store = ContributionStore()

  init() { store.target = target }

  private func contribution(_ fields: [ContributionField: FieldValue] = [:], loras: [LoRASelection] = [], moodboard: [String] = [], start: String? = nil, pipeline: PluginPipeline? = nil) -> PluginContribution {
    PluginContribution(
      fields: FieldOverlay(fields), loras: loras, moodboard: moodboard.map { PluginImageRef(name: $0, path: "/tmp/\($0)") },
      startImage: start.map { PluginImageRef(name: $0, path: "/tmp/\($0)") }, pipeline: pipeline)
  }

  private func pipeline(_ passes: Int) -> PluginPipeline {
    PluginPipeline(name: "p", steps: Array(repeating: PipelineStep(), count: passes))
  }

  @Test func aValueGoesInTheFieldAndTheFieldIsMarkedForThePlugin() {
    store.receive(contribution([.steps: .int(24), .prompt: .text("a cat")]), from: "a")
    #expect(target.fields.parameters.steps == 24)
    #expect(target.fields.prompt == "a cat")
    #expect(store.marks[.steps] == FieldMark(pluginID: "a", value: .int(24), isOverridden: false))
    #expect(store.marks[.prompt]?.pluginID == "a")
  }

  @Test func theMarkedValueIsTheLimitedOne() {
    store.receive(contribution([.width: .int(1000)]), from: "a")
    #expect(target.fields.parameters.width == 1024)
    #expect(store.marks[.width]?.value == .int(1024))
  }

  @Test func changingTheFieldByHandLosesTheTealAndKeepsThePluginsValue() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    target.fields.parameters.steps = 30
    store.reconcile()
    #expect(store.marks[.steps] == FieldMark(pluginID: "a", value: .int(24), isOverridden: true))
  }

  @Test func typingThePluginsValueBackBringsTheTealBack() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    target.fields.parameters.steps = 30
    store.reconcile()
    target.fields.parameters.steps = 24
    store.reconcile()
    #expect(store.marks[.steps]?.isOverridden == false)
  }

  @Test func theSamePluginSendingAgainStartsOverEvenAboveAManualChange() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    target.fields.parameters.steps = 30
    store.reconcile()
    store.receive(contribution([.steps: .int(12)]), from: "a")
    #expect(target.fields.parameters.steps == 12)
    #expect(store.marks[.steps] == FieldMark(pluginID: "a", value: .int(12), isOverridden: false))
    #expect(store.conflicts.isEmpty)
  }

  @Test func aValuePluginsSetOverAManualOneNeverMakesAConflict() {
    target.fields.parameters.steps = 30
    store.receive(contribution([.steps: .int(24)]), from: "a")
    #expect(target.fields.parameters.steps == 24)
    #expect(store.conflicts.isEmpty)
  }

  @Test func anotherPluginOnAMarkedFieldIsAConflictAndTheFieldWaits() {
    store.receive(contribution([.steps: .int(24), .shift: .double(3)]), from: "a")
    store.receive(contribution([.steps: .int(8), .shift: .double(3), .guidanceScale: .double(2)]), from: "b")
    #expect(target.fields.parameters.steps == 24)
    #expect(target.fields.parameters.guidanceScale == 2)
    #expect(store.conflicts.count == 1)
    let conflict = store.conflicts[0]
    #expect(conflict.subject == .field(.steps))
    #expect(conflict.current == .init(pluginID: "a", content: .value(.int(24))))
    #expect(conflict.proposed == .init(pluginID: "b", content: .value(.int(8))))
  }

  @Test func theConflictAlsoCountsWhenTheFirstValueWasOverriddenByHand() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    target.fields.parameters.steps = 30
    store.reconcile()
    store.receive(contribution([.steps: .int(8)]), from: "b")
    #expect(store.conflicts.count == 1)
    #expect(target.fields.parameters.steps == 30)
  }

  @Test func choosingTheNewPluginPutsItsValueInWithTheTeal() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    store.receive(contribution([.steps: .int(8)]), from: "b")
    store.choose(store.conflicts[0].id, proposed: true)
    #expect(target.fields.parameters.steps == 8)
    #expect(store.marks[.steps] == FieldMark(pluginID: "b", value: .int(8), isOverridden: false))
    #expect(store.conflicts.isEmpty)
  }

  @Test func choosingTheCurrentPluginLeavesEverythingAsItIs() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    store.receive(contribution([.steps: .int(8)]), from: "b")
    store.choose(store.conflicts[0].id, proposed: false)
    #expect(target.fields.parameters.steps == 24)
    #expect(store.marks[.steps]?.pluginID == "a")
    #expect(store.conflicts.isEmpty)
  }

  @Test func escapeLeavesTheFieldsAsTheyAre() {
    store.receive(contribution([.steps: .int(24), .shift: .double(1)]), from: "a")
    store.receive(contribution([.steps: .int(8), .shift: .double(2)]), from: "b")
    #expect(store.conflicts.count == 2)
    store.dismissConflicts()
    #expect(store.conflicts.isEmpty)
    #expect(target.fields.parameters.steps == 24)
    #expect(target.fields.parameters.shift == 1)
  }

  @Test func theSamePluginAskingAgainReplacesItsEarlierQuestion() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    store.receive(contribution([.steps: .int(8)]), from: "b")
    store.receive(contribution([.steps: .int(6)]), from: "b")
    #expect(store.conflicts.count == 1)
    #expect(store.conflicts[0].proposed.content == .value(.int(6)))
  }

  @Test func lorasFromDifferentPluginsAddUpWithoutAConflict() {
    store.receive(contribution(loras: [LoRASelection(file: "x.ckpt", weight: 0.5)]), from: "a")
    store.receive(contribution(loras: [LoRASelection(file: "y.ckpt")]), from: "b")
    #expect(target.loraFiles == ["x.ckpt", "y.ckpt"])
    #expect(store.loraPlugins == ["x.ckpt": "a", "y.ckpt": "b"])
    #expect(store.conflicts.isEmpty)
  }

  @Test func aLoRAAlreadyThereTakesTheLastPluginsWeight() {
    store.receive(contribution(loras: [LoRASelection(file: "x.ckpt", weight: 0.5)]), from: "a")
    store.receive(contribution(loras: [LoRASelection(file: "x.ckpt", weight: 0.9)]), from: "b")
    #expect(target.loras.map(\.weight) == [0.9])
    #expect(store.loraPlugins["x.ckpt"] == "b")
  }

  @Test func aLoRATheUserRemovedIsForgotten() {
    store.receive(contribution(loras: [LoRASelection(file: "x.ckpt")]), from: "a")
    target.userRemovesLoRA("x.ckpt")
    store.reconcile()
    #expect(store.loraPlugins.isEmpty)
  }

  @Test func moodboardPicturesFromDifferentPluginsAddUp() {
    store.receive(contribution(moodboard: ["a.png"]), from: "a")
    store.receive(contribution(moodboard: ["b.png"]), from: "b")
    #expect(Set(target.moodboard.values) == ["a.png", "b.png"])
    #expect(Set(store.moodboardPlugins.values) == ["a", "b"])
    #expect(store.conflicts.isEmpty)
  }

  @Test func aPluginSendingItsPicturesAgainReplacesTheOnesItSentBefore() {
    store.receive(contribution(moodboard: ["a.png"]), from: "a")
    store.receive(contribution(moodboard: ["b.png"]), from: "b")
    store.receive(contribution(moodboard: ["a2.png"]), from: "a")
    #expect(Set(target.moodboard.values) == ["a2.png", "b.png"])
  }

  @Test func aPictureThatCannotBeReadIsReportedAndTheRestGoesIn() {
    target.failImages = true
    let problems = store.receive(contribution([.steps: .int(5)], moodboard: ["a.png"]), from: "a")
    #expect(problems.count == 1)
    #expect(target.fields.parameters.steps == 5)
    #expect(store.moodboardPlugins.isEmpty)
  }

  @Test func theStartImageFromTwoPluginsIsAConflict() {
    store.receive(contribution(start: "one.png"), from: "a")
    store.receive(contribution(start: "two.png"), from: "b")
    #expect(target.startImageName == "one.png")
    #expect(store.conflicts.map(\.subject) == [.startImage])
    store.choose(store.conflicts[0].id, proposed: true)
    #expect(target.startImageName == "two.png")
    #expect(store.startImage?.pluginID == "b")
  }

  @Test func aStartImageTheUserReplacedIsNoLongerThePluginsAndMakesNoConflict() {
    store.receive(contribution(start: "one.png"), from: "a")
    target.userRemovesStartImage()
    store.reconcile()
    #expect(store.startImage == nil)
    store.receive(contribution(start: "two.png"), from: "b")
    #expect(store.conflicts.isEmpty)
    #expect(target.startImageName == "two.png")
  }

  @Test func aPipelineFromTwoPluginsIsAConflictAndOneFromTheSamePluginReplaces() {
    store.receive(contribution(pipeline: pipeline(2)), from: "a")
    store.receive(contribution(pipeline: pipeline(3)), from: "a")
    #expect(store.pipeline?.pipeline.steps.count == 3)
    #expect(store.conflicts.isEmpty)
    store.receive(contribution(pipeline: pipeline(1)), from: "b")
    #expect(store.conflicts.count == 1)
    #expect(store.conflicts[0].current.content == .passes(3))
    #expect(store.conflicts[0].proposed.content == .passes(1))
    store.choose(store.conflicts[0].id, proposed: true)
    #expect(store.pipeline?.pluginID == "b")
  }

  @Test func theUserCanTakeThePipelineAway() {
    store.receive(contribution(pipeline: pipeline(2)), from: "a")
    store.removePipeline()
    #expect(store.pipeline == nil)
  }

  @Test func turningAPluginOffTakesItsMarksAndPipelineButKeepsTheValues() {
    store.receive(
      contribution([.steps: .int(24)], loras: [LoRASelection(file: "x.ckpt")], moodboard: ["a.png"], start: "s.png", pipeline: pipeline(2)),
      from: "a")
    store.receive(contribution([.steps: .int(8)]), from: "b")
    #expect(store.conflicts.count == 1)
    store.forget("a")
    #expect(store.marks.isEmpty)
    #expect(store.loraPlugins.isEmpty)
    #expect(store.moodboardPlugins.isEmpty)
    #expect(store.startImage == nil)
    #expect(store.pipeline == nil)
    #expect(store.conflicts.isEmpty)
    #expect(target.fields.parameters.steps == 24)
    #expect(target.loraFiles == ["x.ckpt"])
    #expect(target.moodboard.count == 1)
  }

  @Test func withoutATargetNothingIsTaken() {
    let lonely = ContributionStore()
    #expect(!lonely.receive(contribution([.steps: .int(5)]), from: "a").isEmpty)
    #expect(lonely.marks.isEmpty)
  }
}
