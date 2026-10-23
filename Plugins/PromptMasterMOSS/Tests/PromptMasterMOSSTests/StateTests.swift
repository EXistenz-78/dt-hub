import Foundation
import Testing

@testable import PromptMasterMOSS

@MainActor
struct StateTests {
  static let data = MossData.load(folder: URL(fileURLWithPath: "/nonexistent/DT Hub"))

  func state(storage: MemoryStorage = MemoryStorage()) -> MossState {
    MossState(
      data: Self.data,
      promptFolder: MossPrompts.folder(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent("moss-state-\(UUID().uuidString)")),
      store: MossStore(storage: storage), italian: false, shuffler: { _, _ in [] })
  }

  func ready(_ state: MossState) {
    state.active = true
    state.update(generationSize: PixelSize(width: 1024, height: 640))
    state.document.description = "A scene."
    state.addItem(label: .object, box: FracBox(x0: 0.1, y0: 0.1, x1: 0.5, y1: 0.5))
    state.update(item: 1) { $0.caption = "A cup." }
  }

  @Test func sameRatioChangesAreSilentAndKeepTheBoxes() {
    let state = state()
    ready(state)
    let box = state.document.items[0].box
    state.update(generationSize: PixelSize(width: 1536, height: 960))
    #expect(state.sizeNotice == nil)
    #expect(state.document.items[0].box == box)
  }

  @Test func aDifferentRatioWarnsAndKeepsTheSameFractions() {
    let state = state()
    ready(state)
    let box = state.document.items[0].box
    state.update(generationSize: PixelSize(width: 1024, height: 1024))
    #expect(state.sizeNotice != nil)
    #expect(state.document.items[0].box == box)
    state.dismissSizeNotice()
    #expect(state.sizeNotice == nil)
  }

  @Test func theFirstSizeTheAppReportsIsNotAChange() {
    let state = state()
    state.update(generationSize: PixelSize(width: 1024, height: 640))
    #expect(state.sizeNotice == nil)
  }

  @Test func withoutAUsableSizeNothingCanBeSent() {
    let state = state()
    ready(state)
    #expect(state.canSend)
    state.update(generationSize: nil)
    #expect(!state.canSend && state.problems.contains(.unknownSize) && state.currentJSON() == nil)
    state.update(generationSize: PixelSize(width: 1000, height: 640))
    #expect(!state.canSend && state.currentJSON() == nil)
  }

  @Test func addItemTakesTheNextIDAndOpensTheCard() {
    let state = state()
    state.addItem(label: .text, box: FracBox(x0: 0, y0: 0, x1: 0.2, y1: 0.2))
    state.addItem(label: .panel, box: FracBox(x0: 0, y0: 0, x1: 1, y1: 1))
    #expect(state.document.items.map(\.id) == [1, 2])
    #expect(state.document.items.allSatisfy { $0.expanded })
    #expect(state.document.nextItemID == 3)
    #expect(state.selectedItem == 2)
  }

  @Test func setLabelChangesOnlyTheLabel() {
    let state = state()
    ready(state)
    let before = state.document.items[0]
    state.setLabel(.character, for: 1)
    var expected = before
    expected.label = .character
    #expect(state.document.items[0] == expected)
  }

  @Test func theSizeIsNotRememberedAcrossRuns_theSnapshotIs() {
    let storage = MemoryStorage()
    let first = state(storage: storage)
    ready(first)
    first.document.snapshot = MossSnapshot(description: "prima", selection: [], freeMeta: [], captions: [1: "x"], tags: [:])
    let second = state(storage: storage)
    #expect(second.generationSize == nil)
    #expect(second.document.snapshot?.description == "prima")
    #expect(second.document.items.count == 1)
  }

  @Test func switchingProjectLoadsThatProjectsDocumentAndClearsTheReview() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("moss-project-\(UUID().uuidString)")
    var session = MossSession()
    session.document.description = "del progetto"
    MossStore(storage: FileStorage(folder: folder)).save(session)
    let state = state()
    state.update(generationSize: PixelSize(width: 1024, height: 640))
    state.update(generationSize: PixelSize(width: 1024, height: 1024))
    state.switchProject(folder: folder, adoptLegacy: false)
    #expect(state.document.description == "del progetto")
    #expect(state.sizeNotice == nil && state.selectedItem == nil)
  }
}
