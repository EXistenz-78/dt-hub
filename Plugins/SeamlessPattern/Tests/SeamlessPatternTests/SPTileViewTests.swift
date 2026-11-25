import CoreGraphics
import Testing

@testable import SeamlessPattern

@Suite("SPTileView")
struct SPTileViewTests {
  /// 64x32 picture whose every pixel tells where it is.
  private let tile = TestImages.make(64, 32) { x, y, c in c == 0 ? x : c == 1 ? y : 7 }

  @Test func twoByTwoRepeatsTheTileInFourQuadrants() throws {
    let out = try #require(SPTileView.render(tile, view: .twoByTwo))
    #expect(out.width == 128 && out.height == 64)
    for (qx, qy) in [(0, 0), (64, 0), (0, 32), (64, 32)] {
      #expect(TestImages.pixel(out, qx + 5, qy + 9) == [5, 9, 7])
    }
  }

  @Test func threeByThreeIsNineCopies() throws {
    let out = try #require(SPTileView.render(tile, view: .threeByThree))
    #expect(out.width == 192 && out.height == 96)
    #expect(TestImages.pixel(out, 128 + 2, 64 + 3) == [2, 3, 7])
  }

  @Test func tileIsThePictureItself() throws {
    let out = try #require(SPTileView.render(tile, view: .tile))
    #expect(out.width == 64 && out.height == 32)
    #expect(TestImages.pixel(out, 10, 20) == [10, 20, 7])
  }

  @Test func offsetMovesByHalfATileBothWays() throws {
    let out = try #require(SPTileView.render(tile, view: .offset))
    #expect(out.width == 64 && out.height == 32)
    // The pixel that was at (0, 0) is now at (32, 16); the one at (63, 31) wraps to (31, 15).
    #expect(TestImages.pixel(out, 32, 16) == [0, 0, 7])
    #expect(TestImages.pixel(out, 31, 15) == [63, 31, 7])
  }

  @Test func halfDropIsThreeColumnsTheMiddleOneMovedDown() throws {
    let out = try #require(SPTileView.render(tile, view: .halfDrop))
    #expect(out.width == 3 * 64 && out.height == 2 * 32)
    #expect(TestImages.pixel(out, 3, 4) == [3, 4, 7])
    #expect(TestImages.pixel(out, 64 + 3, 16 + 4) == [3, 4, 7])
    #expect(TestImages.pixel(out, 128 + 3, 4) == [3, 4, 7])
  }

  @Test func halfBrickIsThreeRowsTheMiddleOneMovedRight() throws {
    let out = try #require(SPTileView.render(tile, view: .halfBrick))
    #expect(out.width == 2 * 64 && out.height == 3 * 32)
    #expect(TestImages.pixel(out, 3, 4) == [3, 4, 7])
    #expect(TestImages.pixel(out, 32 + 3, 32 + 4) == [3, 4, 7])
    #expect(TestImages.pixel(out, 3, 64 + 4) == [3, 4, 7])
  }
}
