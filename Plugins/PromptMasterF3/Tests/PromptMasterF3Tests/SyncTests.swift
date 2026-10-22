import Testing

@testable import PromptMasterF3

struct SyncTests {
  let box = BBox(y0: 0, x0: 0, y1: 180, x1: 180)

  func apply(_ sync: inout F3Sync, _ old: String, _ new: String) -> F3SyncChange {
    sync.apply(oldText: old, newText: new, makeBox: { _ in BBox(y0: 0, x0: 0, y1: 180, x1: 180) })
  }

  @Test func newIDsBecomeElementsInOrderWithDistinctColors() {
    var sync = F3Sync()
    let change = apply(&sync, "", "<a> and <b>")
    #expect(sync.elements.map(\.id) == ["a", "b"])
    #expect(change.added == ["a", "b"])
    #expect(sync.elements.map(\.colorIndex) == [0, 1])
  }

  @Test func boxFactoryGetsTheIndex() {
    var sync = F3Sync()
    var indexes: [Int] = []
    _ = sync.apply(oldText: "", newText: "<a><b><c>", makeBox: { indexes.append($0); return BBox(y0: 0, x0: 0, y1: 20, x1: 20) })
    #expect(indexes == [0, 1, 2])
  }

  @Test func removedIDRemovesElementAndIsRemembered() {
    var sync = F3Sync()
    _ = apply(&sync, "", "<a> <b>")
    sync.elements[0].desc = "keep me"
    sync.elements[0].box = BBox(y0: 100, x0: 100, y1: 300, x1: 300)
    let change = apply(&sync, "<a> <b>", "<b>")
    #expect(sync.elements.map(\.id) == ["b"])
    #expect(change.removed == ["a"])
    #expect(sync.removed["a"]?.desc == "keep me")
  }

  @Test func returningIDRestoresDescAndBox() {
    var sync = F3Sync()
    _ = apply(&sync, "", "<a>")
    sync.elements[0].desc = "keep me"
    sync.elements[0].box = BBox(y0: 100, x0: 100, y1: 300, x1: 300)
    _ = apply(&sync, "<a>", "")
    #expect(sync.elements.isEmpty)
    _ = apply(&sync, "", "<a>")
    #expect(sync.elements.first?.desc == "keep me")
    #expect(sync.elements.first?.box == BBox(y0: 100, x0: 100, y1: 300, x1: 300))
    #expect(sync.removed["a"] == nil)
  }

  @Test func renameKeepsCardBoxAndColor() {
    var sync = F3Sync()
    _ = apply(&sync, "", "a woman <woman_1> here")
    sync.elements[0].desc = "d"
    let color = sync.elements[0].colorIndex
    let change = apply(&sync, "a woman <woman_1> here", "a woman <girl_1> here")
    #expect(sync.elements.count == 1)
    #expect(sync.elements[0].id == "girl_1")
    #expect(sync.elements[0].desc == "d")
    #expect(sync.elements[0].colorIndex == color)
    #expect(change.renamed == [F3Rename(from: "woman_1", to: "girl_1")])
    #expect(change.added.isEmpty && change.removed.isEmpty)
  }

  @Test func repeatedIDGivesOneCardAndAReport() {
    var sync = F3Sync()
    let change = apply(&sync, "", "<l_1> next to <l_1>")
    #expect(sync.elements.map(\.id) == ["l_1"])
    #expect(change.duplicates == ["l_1"])
  }

  @Test func openTagMakesNothing() {
    var sync = F3Sync()
    _ = apply(&sync, "", "a woman <woman_")
    #expect(sync.elements.isEmpty)
  }

  @Test func colorsNeverChangeWhenOthersAreRemoved() {
    var sync = F3Sync()
    _ = apply(&sync, "", "<a><b><c>")
    let colorOfC = sync.elements[2].colorIndex
    _ = apply(&sync, "<a><b><c>", "<a><c>")
    #expect(sync.elements.first { $0.id == "c" }?.colorIndex == colorOfC)
    _ = apply(&sync, "<a><c>", "<a><c><d>")
    #expect(sync.elements.last?.colorIndex == 3)
  }
}
