import Testing

@testable import TiledUpscaleLab

struct TUFadeTests {
  @Test func leftNeighbourOnly() {
    // First row, second column: the neighbour's result is the left 256 columns.
    func w(_ x: Int, _ y: Int = 500) -> Double { TUFade.weight(x: x, y: y, column: 1, row: 0, overlap: 256, fade: 48) }
    #expect(w(256) == 0 && w(300) == 0, "the new part is the source")
    #expect(w(208) == 1 && w(100) == 1, "deep in the neighbour's part it is the neighbour's")
    #expect(abs(w(232) - 0.5) < 0.001, "half way")
    #expect(w(255) < 0.01)
  }

  @Test func topNeighbourOnly() {
    func w(_ x: Int, _ y: Int) -> Double { TUFade.weight(x: x, y: y, column: 0, row: 1, overlap: 256, fade: 48) }
    #expect(w(500, 256) == 0 && w(500, 400) == 0)
    #expect(w(500, 208) == 1 && w(500, 10) == 1)
    #expect(abs(w(500, 232) - 0.5) < 0.001)
  }

  @Test func bothNeighboursRoundTheCorner() {
    func w(_ x: Int, _ y: Int) -> Double { TUFade.weight(x: x, y: y, column: 1, row: 1, overlap: 256, fade: 48) }
    #expect(w(100, 300) == 1, "left strip, below the top one")
    #expect(w(300, 100) == 1, "top strip, right of the left one")
    #expect(w(300, 300) == 0)
    #expect(w(250, 250) < 0.15, "near the inner corner the source takes over, in a round shape")
    #expect(w(100, 100) == 1)
  }

  @Test func noFadeIsAHardEdgeAndTheFirstTileHasNothingToFade() {
    #expect(TUFade.weight(x: 255, y: 500, column: 1, row: 0, overlap: 256, fade: 0) == 1)
    #expect(TUFade.weight(x: 256, y: 500, column: 1, row: 0, overlap: 256, fade: 0) == 0)
    #expect(TUFade.weight(x: 10, y: 10, column: 0, row: 0, overlap: 256, fade: 48) == 0)
  }
}
