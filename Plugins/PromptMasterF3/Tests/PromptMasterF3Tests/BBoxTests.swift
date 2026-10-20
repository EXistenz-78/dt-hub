import Testing

@testable import PromptMasterF3

struct BBoxTests {
  @Test func parsesFourNumbers() {
    #expect(BBox.parse("[10, 20, 300, 400]") == BBox(y0: 10, x0: 20, y1: 300, x1: 400))
    #expect(BBox.parse("10 20 300 400") == BBox(y0: 10, x0: 20, y1: 300, x1: 400))
  }

  @Test func normalizesOrderAndClamps() {
    #expect(BBox.normalized(y0: 500, x0: 900, y1: 100, x1: 1200) == BBox(y0: 100, x0: 900, y1: 500, x1: 1000))
  }

  @Test func rejectsSidesShorterThanTwenty() {
    #expect(BBox.normalized(y0: 0, x0: 0, y1: 19, x1: 500) == nil)
    #expect(BBox.parse("0 0 500 10") == nil)
  }

  @Test func gridComesFromTheScale() {
    #expect(BBox.grid == BBoxScale.grid)
    #expect(BBoxScale.grid == 1000)
  }

  @Test func resolveKeepsCurrentWhenHalfTyped() {
    let current = BBox(y0: 1, x0: 2, y1: 300, x1: 400)
    #expect(BBox.resolve("12, 3", current: current) == current)
    #expect(BBox.resolve("  ", current: current) == nil)
  }
}
