import Foundation

/// The values the geometry rests on, in one place (spec §3): nothing else in the plug-in assumes 1024, 256 or 320.
enum TileConstants {
  /// The longest side of a tile, in pixels (a multiple of 64, as Draw Things works).
  static let tile = 1024
  /// The part of the overlap the mask leaves free, towards the tiles already made: 200 of 256, 250 of 320.
  static let freeFactor = 25.0 / 32.0
}

/// How much two neighbouring tiles share. A multiple of 64, so the step between tiles is too.
enum TileOverlap: Int, CaseIterable, Sendable {
  case standard = 256
  case wide = 320

  /// Distance between the starts of two neighbouring tiles.
  var step: Int { TileConstants.tile - rawValue }
  /// Pixels of the overlap the mask leaves free (not a multiple of 64: a mask edge needs none).
  var free: Int { Int((Double(rawValue) * TileConstants.freeFactor).rounded()) }
}

struct TileRect: Equatable, Sendable {
  var x: Int
  var y: Int
  var width: Int
  var height: Int
}

/// The size of the enlarged picture once cut to a multiple of 64, and how much was cut on the left and on top.
struct ScaledSize: Equatable, Sendable {
  let width: Int
  let height: Int
  let cropLeft: Int
  let cropTop: Int
}

struct Tile: Equatable, Sendable {
  let index: Int
  let row: Int
  let column: Int
  /// Where the tile is in the enlarged picture.
  let rect: TileRect
  /// The part to regenerate, in the tile's own coordinates; nil for the first tile (all of it is new).
  let maskRect: TileRect?
}

struct TilePlan: Equatable, Sendable {
  let width: Int
  let height: Int
  let overlap: TileOverlap
  let columns: Int
  let rows: Int
  let tiles: [Tile]
  var count: Int { tiles.count }
}

enum TileGrid {
  /// The enlarged picture cut to the lower multiple of 64, centered (the extra pixel goes right and down).
  static func scaledSize(width: Int, height: Int, factor: Int) -> ScaledSize {
    func cut(_ side: Int) -> (size: Int, before: Int) {
      let enlarged = side * factor
      let size = enlarged / 64 * 64
      return (size, (enlarged - size) / 2)
    }
    let (w, left) = cut(width)
    let (h, top) = cut(height)
    return ScaledSize(width: w, height: h, cropLeft: left, cropTop: top)
  }

  /// The tiles of a picture already cut to multiples of 64, row by row from the top left.
  static func plan(width: Int, height: Int, overlap: TileOverlap) -> TilePlan {
    let columns = spans(for: width, step: overlap.step)
    let rows = spans(for: height, step: overlap.step)
    var tiles: [Tile] = []
    for (row, y) in rows.enumerated() {
      for (column, x) in columns.enumerated() {
        let rect = TileRect(
          x: x, y: y, width: min(TileConstants.tile, width - x), height: min(TileConstants.tile, height - y))
        tiles.append(
          Tile(
            index: tiles.count, row: row, column: column, rect: rect,
            maskRect: maskRect(row: row, column: column, size: rect, free: overlap.free)))
      }
    }
    return TilePlan(
      width: width, height: height, overlap: overlap, columns: columns.count, rows: rows.count, tiles: tiles)
  }

  /// The starts of the tiles along one side: one tile when the side fits, else as many steps as it takes to reach the end.
  private static func spans(for side: Int, step: Int) -> [Int] {
    guard side > TileConstants.tile else { return [0] }
    let count = (side - TileConstants.tile + step - 1) / step + 1
    return (0..<count).map { $0 * step }
  }

  private static func maskRect(row: Int, column: Int, size: TileRect, free: Int) -> TileRect? {
    switch (row == 0, column == 0) {
    case (true, true): nil
    case (true, false): TileRect(x: free, y: 0, width: size.width - free, height: size.height)
    case (false, true): TileRect(x: 0, y: free, width: size.width, height: size.height - free)
    case (false, false): TileRect(x: free, y: free, width: size.width - free, height: size.height - free)
    }
  }
}
