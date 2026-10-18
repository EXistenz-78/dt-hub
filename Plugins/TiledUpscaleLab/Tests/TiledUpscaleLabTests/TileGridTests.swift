import Testing

@testable import TiledUpscaleLab

struct TileGridTests {
  @Test func scaledSizeKeepsAMultipleOf64() {
    let size = TileGrid.scaledSize(width: 1024, height: 768, factor: 4)
    #expect(size == ScaledSize(width: 4096, height: 3072, cropLeft: 0, cropTop: 0))
  }

  @Test func scaledSizeCropsToTheLowerMultipleOf64Centered() {
    let even = TileGrid.scaledSize(width: 1000, height: 1000, factor: 2)
    #expect(even == ScaledSize(width: 1984, height: 1984, cropLeft: 8, cropTop: 8))
    let odd = TileGrid.scaledSize(width: 1001, height: 1000, factor: 2)
    #expect(odd.width == 1984)
    #expect(odd.cropLeft == 9)
    let sixtyThree = TileGrid.scaledSize(width: 2047, height: 64, factor: 1)
    #expect(sixtyThree.width == 1984)
    #expect(sixtyThree.cropLeft == 31)
  }

  @Test func oneTileWhenTheSideIsAtMost1024() {
    let plan = TileGrid.plan(width: 1024, height: 1024, overlap: .standard)
    #expect(plan.count == 1)
    #expect(plan.tiles[0].maskRect == nil)
    let small = TileGrid.plan(width: 640, height: 512, overlap: .standard)
    #expect(small.count == 1)
    #expect(small.tiles[0].rect == TileRect(x: 0, y: 0, width: 640, height: 512))
  }

  @Test func columnsStartAtMultiplesOfTheStep() {
    let standard = TileGrid.plan(width: 2688, height: 1024, overlap: .standard, free: 200)
    #expect(standard.tiles.map(\.rect.x) == [0, 768, 1536, 2304])
    #expect(standard.tiles.last?.rect.width == 384)
    let wide = TileGrid.plan(width: 2688, height: 1024, overlap: .wide)
    #expect(wide.tiles.map(\.rect.x) == [0, 704, 1408, 2112])
  }

  @Test func lastTileIsWiderThanTheOverlapAndAMultipleOf64() {
    for overlap in TileOverlap.allCases {
      for side in stride(from: 1088, through: 8192, by: 64) {
        let plan = TileGrid.plan(width: side, height: 1024, overlap: overlap)
        for tile in plan.tiles {
          #expect(tile.rect.width % 64 == 0 && tile.rect.height % 64 == 0)
          #expect(tile.rect.width <= 1024)
        }
        let last = plan.tiles.last!.rect
        #expect(last.width > overlap.rawValue)
        #expect(last.x + last.width == side)
      }
    }
  }

  @Test func tilesAreRowMajor() {
    let plan = TileGrid.plan(width: 2048, height: 2048, overlap: .standard)
    #expect(plan.columns == 3 && plan.rows == 3)
    #expect(plan.tiles.map(\.index) == Array(0..<9))
    #expect(plan.tiles[1].row == 0 && plan.tiles[1].column == 1)
    #expect(plan.tiles[3].row == 1 && plan.tiles[3].column == 0)
  }

  @Test func maskRectsFollowTheFourCases() {
    for overlap in TileOverlap.allCases {
      let free = overlap == .standard ? 200 : 250
      let plan = TileGrid.plan(width: 2048, height: 2048, overlap: overlap, free: free)
      let w = { (i: Int) in plan.tiles[i].rect.width }
      let h = { (i: Int) in plan.tiles[i].rect.height }
      #expect(plan.tiles[0].maskRect == nil)
      #expect(plan.tiles[1].maskRect == TileRect(x: free, y: 0, width: w(1) - free, height: h(1)))
      #expect(plan.tiles[3].maskRect == TileRect(x: 0, y: free, width: w(3), height: h(3) - free))
      #expect(plan.tiles[4].maskRect == TileRect(x: free, y: free, width: w(4) - free, height: h(4) - free))
    }
    let narrow = TileGrid.plan(width: 1088, height: 1024, overlap: .standard, free: 200)
    #expect(narrow.tiles[1].rect.width == 320)
    #expect(narrow.tiles[1].maskRect?.width == 120)
    #expect(TileGrid.plan(width: 2048, height: 1024, overlap: .standard, free: 100).tiles[1].maskRect?.x == 100, "the free margin is the plan's own")
  }

  @Test func countMatchesTheSpecExample() {
    #expect(TileGrid.plan(width: 8192, height: 8192, overlap: .standard).count == 121)
    #expect(TileGrid.plan(width: 8192, height: 8192, overlap: .wide).count == 144)
  }

  @Test func aBiggerTileMeansFewerTiles() {
    let big = TileGrid.plan(width: 4096, height: 1024, overlap: .standard, tile: 2048)
    #expect(big.tiles.map(\.rect.x) == [0, 1792, 3584])
    #expect(big.tiles.map(\.rect.width) == [2048, 2048, 512], "the last tile is what is left of the side, wider than the overlap")
    let mid = TileGrid.plan(width: 4096, height: 1024, overlap: .standard, tile: 1536)
    #expect(mid.tiles.map(\.rect.x) == [0, 1280, 2560])
    #expect(mid.tiles.last?.rect.width == 1536)
    #expect(TileGrid.plan(width: 3968, height: 3968, overlap: .standard, tile: 1024).count == 25)
    #expect(TileGrid.plan(width: 3968, height: 3968, overlap: .standard, tile: 2048).count == 9)
  }

  @Test func everyTileSizeKeepsTheTilesAMultipleOf64AndInsideTheSize() {
    for tile in stride(from: 1024, through: 2048, by: 64) {
      for overlap in TileOverlap.allCases {
        for side in [2560, 3968, 4096, 8192] {
          let plan = TileGrid.plan(width: side, height: 1024, overlap: overlap, tile: tile)
          for t in plan.tiles {
            #expect(t.rect.width % 64 == 0 && t.rect.width <= tile, "tile \(tile) overlap \(overlap.rawValue) side \(side)")
          }
          let last = plan.tiles.last!.rect
          #expect(last.x + last.width == side && last.width > overlap.rawValue)
        }
      }
    }
  }
}
