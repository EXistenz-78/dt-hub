import Testing

@testable import PromptMasterF3

struct DefaultBoxTests {
  @Test func firstBoxIsAtTheTopLeftAndSquareOnSquareCanvas() {
    #expect(F3DefaultBox.box(index: 0, aspect: 1, taken: []) == BBox(y0: 0, x0: 0, y1: 180, x1: 180))
  }

  @Test func nextBoxesGoToTheRightWithStep200() {
    #expect(F3DefaultBox.box(index: 1, aspect: 1, taken: []).x0 == 200)
    #expect(F3DefaultBox.box(index: 4, aspect: 1, taken: []).x0 == 800)
  }

  @Test func rowWrapsAfterFiveBoxes() {
    let box = F3DefaultBox.box(index: 5, aspect: 1, taken: [])
    #expect(box.x0 == 0)
    #expect(box.y0 == 200)
  }

  @Test func boxIsSquareInPixelsOnWideCanvas() {
    let box = F3DefaultBox.box(index: 0, aspect: 1.5, taken: [])
    #expect(box.x1 - box.x0 == 180)
    #expect(box.y1 - box.y0 == 270)
  }

  @Test func rowsDoNotOverlapOnTallBoxes() {
    let first = F3DefaultBox.box(index: 0, aspect: 1.5, taken: [])
    let second = F3DefaultBox.box(index: 5, aspect: 1.5, taken: [])
    #expect(second.y0 >= first.y1)
  }

  @Test func fullGridStaysInsideAndAvoidsTaken() {
    var taken: [BBox] = []
    for index in 0..<120 {
      let box = F3DefaultBox.box(index: index, aspect: 1, taken: taken)
      #expect(box.y0 >= 0 && box.x0 >= 0 && box.y1 <= 1000 && box.x1 <= 1000)
      #expect(box.y1 - box.y0 >= BBox.minSide && box.x1 - box.x0 >= BBox.minSide)
      #expect(!taken.contains(box))
      taken.append(box)
    }
  }

  @Test func veryTallCanvasKeepsHeightWithinTheGrid() {
    let box = F3DefaultBox.box(index: 0, aspect: 10, taken: [])
    #expect(box.y1 <= 1000)
  }

  @Test func veryWideCanvasKeepsMinimumSide() {
    let box = F3DefaultBox.box(index: 0, aspect: 0.01, taken: [])
    #expect(box.y1 - box.y0 >= BBox.minSide)
  }
}
