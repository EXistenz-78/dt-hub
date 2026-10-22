import CoreGraphics
import Testing

@testable import Flux3Editing

struct NumberingTests {
  private func refs(_ names: [String]) -> [RefImage] {
    RefNumbering.references(moodboard: names.map { "/store/\($0)" }, sizes: { _ in CGSize(width: 300, height: 200) })
  }

  @Test func theStartImageIsZeroAndTheMoodboardFollowsFromOne() {
    let list = refs(["a.png", "b.png", "c.png"])
    #expect(RefNumbering.startImageNumber == 0)
    #expect(list.map(\.number) == [1, 2, 3])
    #expect(list.map(\.fileName) == ["a.png", "b.png", "c.png"])
    #expect(list[0].size == CGSize(width: 300, height: 200))
  }

  @Test func anUnreadableImageGetsAUnitSizeSoItCanStillBeShown() {
    let list = RefNumbering.references(moodboard: ["/store/a.png"], sizes: { _ in nil })
    #expect(list[0].size == CGSize(width: 1, height: 1))
  }

  @Test func referenceFollowsTheFileWhenReordered() {
    let before = refs(["a.png", "b.png", "c.png"])
    let after = refs(["c.png", "a.png", "b.png"])
    #expect(RefNumbering.number(ofFile: "a.png", in: before) == 1)
    #expect(RefNumbering.number(ofFile: "a.png", in: after) == 2)
    #expect(RefNumbering.number(ofFile: "c.png", in: after) == 1)
  }

  @Test func aFileThatLeftTheMoodboardHasNoNumber() {
    #expect(RefNumbering.number(ofFile: "b.png", in: refs(["a.png", "c.png"])) == nil)
  }
}
