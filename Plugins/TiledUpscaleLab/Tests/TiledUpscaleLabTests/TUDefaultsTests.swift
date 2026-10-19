import Foundation
import Testing

@testable import TiledUpscaleLab

@MainActor
struct TUDefaultsTests {
  let folder = TestImages.temporaryFolder()

  @Test func theDefaultsFollowTheOverlap() {
    #expect(TUSettings.defaults(for: .standard) == TUSettings(free: 192, blur: 30, outset: 29, fade: 64, tile: 1024, toneStrength: 100, toneRadius: 16))
    #expect(TUSettings.defaults(for: .wide) == TUSettings(free: 256, blur: 30, outset: 29, fade: 64, tile: 1024, toneStrength: 100, toneRadius: 16))
    #expect(TUSettings.standard == TUSettings.defaults(for: .standard))
    // The fade of the defaults is all that the free part leaves of the overlap: nothing is clamped away.
    for overlap in TileOverlap.allCases {
      #expect(TUSettings.defaults(for: overlap).clamped(overlap: overlap) == TUSettings.defaults(for: overlap))
    }
  }

  @Test func theTileIsTheSmallestThatNeedsAtMostThreeAlongTheShortSide() {
    #expect(TUSettings.autoTile(shortestSide: 3712, overlap: .standard) == 1408, "the screenshot with 256")
    #expect(TUSettings.autoTile(shortestSide: 4160, overlap: .wide) == 1600, "the screenshot with 320")
    #expect(TUSettings.autoTile(shortestSide: 3968, overlap: .wide) == 1536)
    #expect(TUSettings.autoTile(shortestSide: 1000, overlap: .standard) == 1024, "never under 1024")
    #expect(TUSettings.autoTile(shortestSide: 9000, overlap: .standard) == 2048, "never over 2048")
  }

  @Test func withTheAutomaticTileTheShortSideNeverNeedsMoreThanThreeTiles() {
    for overlap in TileOverlap.allCases {
      for side in stride(from: 1024, through: 5440, by: 64) {
        let tile = TUSettings.autoTile(shortestSide: side, overlap: overlap)
        #expect(tile % 64 == 0 && (1024...2048).contains(tile))
        let plan = TileGrid.plan(width: side, height: side, overlap: overlap, tile: tile)
        #expect(plan.columns <= 3 && plan.rows <= 3, "side \\(side) overlap \\(overlap.rawValue) tile \\(tile)")
      }
    }
  }

  @Test func theEnlargementIsTwoOrFour() {
    #expect(TUState.factors == [2, 4])
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? Data(#"{"factor":8,"overlap":256,"loraWeight":1}"#.utf8).write(to: folder.appendingPathComponent("state.json"))
    #expect(TUStore(folder: folder).load().factor == 4, "a project that had 8× gets 4×")
  }

  @Test func theTileSizeSetsItselfFromThePictureTheEnlargementAndTheOverlap() {
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.setImage(TestImages.solid(1000, 1000, (1, 2, 3)), name: "a")
    s.factor = 4
    #expect(s.tileSize == 1536 && s.summary?.passes == 9)
    s.overlap = .wide
    #expect(s.tileSize == 1536)
    s.factor = 2
    #expect(s.tileSize == 1024, "1984 px: (1984 + 640) / 3 is under 1024")
    s.setImage(TestImages.solid(1300, 900, (1, 2, 3)), name: "b")
    #expect(s.tileSize == 1024)
  }

  @Test func aTileSizeSetByHandStaysUntilSomethingElseChangesIt() {
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.setImage(TestImages.solid(1000, 1000, (1, 2, 3)), name: "a")
    s.factor = 4
    s.tileSize = 1792
    #expect(s.tileSize == 1792)
    s.maskBlur = 12
    #expect(s.tileSize == 1792, "the advanced values do not touch it")
    s.factor = 2
    s.factor = 4
    #expect(s.tileSize == 1536)
  }

  @Test func theFreePartGoesBackToTheDefaultOfTheOverlapAndTheRestStays() {
    let s = TUState(store: TUStore(folder: nil), italian: false)
    #expect(s.maskFree == 192)
    s.maskBlur = 12
    s.overlap = .wide
    #expect(s.maskFree == 256 && s.maskBlur == 12)
    s.overlap = .standard
    #expect(s.maskFree == 192)
  }

  @Test func theLoadedValuesAreNotReplacedByTheDefaultsOfTheOverlap() {
    let one = folder.appendingPathComponent("one")
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.switchProject(folder: one)
    s.overlap = .wide
    s.maskFree = 100
    s.tileSize = 1280
    s.switchProject(folder: folder.appendingPathComponent("other"))
    s.switchProject(folder: one)
    #expect(s.overlap == .wide && s.maskFree == 100 && s.tileSize == 1280)
  }

  @Test func theButtonRestoresTheAdvancedDefaultsOfTheOverlap() {
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.overlap = .wide
    s.maskFree = 100; s.maskBlur = 5; s.maskOutset = 70; s.junctionFade = 10; s.toneStrength = 30; s.toneRadius = 200
    s.resetAdvanced()
    let d = TUSettings.defaults(for: .wide)
    #expect(s.maskFree == d.free && s.maskBlur == d.blur && s.maskOutset == d.outset && s.junctionFade == d.fade)
    #expect(s.toneStrength == d.toneStrength && s.toneRadius == d.toneRadius)
  }
}
