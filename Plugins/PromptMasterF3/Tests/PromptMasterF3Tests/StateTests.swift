import Foundation
import Testing

@testable import PromptMasterF3

@MainActor
struct StateTests {
  func makeState(storage: MemoryStorage = MemoryStorage(), sleep: @escaping @Sendable (Duration) async -> Void = { _ in try? await Task.sleep(for: .seconds(3600)) }) -> F3State {
    F3State(
      promptFolder: F3Prompts.folder(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
      store: F3Store(storage: storage), italian: true, shuffler: { _, _ in [] }, sleep: sleep)
  }

  @Test func typingDoesNotCreateElementsBeforeTheDelay() {
    let state = makeState()
    state.compositionChanged("a woman <woman_1>")
    #expect(state.document.elements.isEmpty)
    state.commitComposition()
    #expect(state.document.elements.map(\.id) == ["woman_1"])
  }

  @Test func halfTypedTagMakesNothing() {
    let state = makeState()
    state.compositionChanged("a woman <woman_")
    state.commitComposition()
    #expect(state.document.elements.isEmpty)
  }

  @Test func delayedSyncHappensAfterTheSleep() async {
    let state = makeState(sleep: { _ in })
    state.compositionChanged("<a> <b>")
    await state.pendingSync?.value
    #expect(state.document.elements.map(\.id) == ["a", "b"])
  }

  @Test func newElementsGetDistinctColorsAndBoxes() {
    let state = makeState()
    state.compositionChanged("<a> <b> <c>")
    state.commitComposition()
    #expect(Set(state.document.elements.map(\.colorIndex)).count == 3)
    #expect(Set(state.document.elements.map(\.box)).count == 3)
  }

  @Test func descriptionsAndBoxesSurviveALaterSync() {
    let state = makeState()
    state.compositionChanged("<a>")
    state.commitComposition()
    state.update(element: "a") { $0.desc = "mine"; $0.box = BBox(y0: 100, x0: 100, y1: 300, x1: 300) }
    state.compositionChanged("<a> and <b>")
    state.commitComposition()
    #expect(state.document.element("a")?.desc == "mine")
    #expect(state.document.element("a")?.box == BBox(y0: 100, x0: 100, y1: 300, x1: 300))
  }

  @Test func canSendNeedsDescriptionsAndNoDuplicates() {
    let state = makeState()
    state.active = true
    state.compositionChanged("<a>")
    state.commitComposition()
    #expect(!state.canSend)
    state.update(element: "a") { $0.desc = "x" }
    #expect(state.canSend)
    state.compositionChanged("<a> <a>")
    state.commitComposition()
    #expect(state.problems.contains(.duplicateID("a")))
    #expect(!state.canSend)
  }

  @Test func canSendIsFalseWhileASyncIsPending() {
    let state = makeState()
    state.active = true
    state.compositionChanged("<a>")
    state.commitComposition()
    state.update(element: "a") { $0.desc = "x" }
    state.compositionChanged("<a> <b>")
    #expect(!state.canSend)
  }

  @Test func removingACardRemovesItsTagFromTheText() {
    let state = makeState()
    state.compositionChanged("A woman <w_1> and a lamp <l_1>.")
    state.commitComposition()
    state.removeElement("w_1")
    #expect(state.document.composition == "A woman  and a lamp <l_1>.")
    #expect(state.document.elements.map(\.id) == ["l_1"])
  }

  @Test func projectSwitchLoadsTheOtherSession() throws {
    let state = makeState()
    state.compositionChanged("<a>")
    state.commitComposition()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    state.switchProject(folder: folder, adoptLegacy: false)
    #expect(state.document.elements.isEmpty)
    state.compositionChanged("<z>")
    state.commitComposition()
    state.switchProject(folder: folder, adoptLegacy: false)
    #expect(state.document.elements.map(\.id) == ["z"])
  }

  @Test func snapshotSurvivesARestart() {
    let storage = MemoryStorage()
    let first = makeState(storage: storage)
    first.document.snapshot = F3Snapshot(description: "old", selection: [], composition: "<a>", descs: ["a": "d"])
    let second = makeState(storage: storage)
    #expect(second.document.snapshot?.description == "old")
    #expect(second.canUndo)
  }

  @Test func sendTextUsesTermsAndComposer() {
    let state = makeState()
    state.document.description = "A scene."
    state.compositionChanged("<a>")
    state.commitComposition()
    state.update(element: "a") { $0.desc = "d"; $0.box = BBox(y0: 20, x0: 30, y1: 300, x1: 400) }
    #expect(state.sendText.hasPrefix("A scene.\n\n<a>\n\n["))
    #expect(state.sendText.contains("\"bbox\": [20, 30, 300, 400]"))
  }
}
