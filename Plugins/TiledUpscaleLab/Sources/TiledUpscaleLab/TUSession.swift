import CoreGraphics
import Foundation

/// One enlargement, from the app's questions (`session.next`) to the composed picture (spec §7.2). It cuts the tiles out of
/// the enlarged picture, puts each result back before cutting the next (so the overlap of a tile is already enlarged), and
/// answers each question with the pass for the next tile. It is used from one task at a time.
final class TUSession: @unchecked Sendable {
  let plan: TilePlan
  /// What went wrong (a result that does not fit its tile), nil while all is well.
  private(set) var problem: String?

  private let source: CGImage
  private let factor: Int
  private let scaled: ScaledSize
  private let settings: TUSettings
  private let overlap: TileOverlap
  private let loraWeight: Double
  private let trigger: String
  private let preset: TUPreset
  private let tempFolder: URL
  private var canvas: TUCanvas?
  /// The enlarged source alone, kept only when the join is faded (the fade mixes it with what the neighbours made).
  private var baseCanvas: TUCanvas?
  /// The small picture of the tiles that are back (spec of the preview): see `previewImage()`.
  private var previewCanvas: TUCanvas?
  private let previewScale: Double
  /// How many tiles are back and composed.
  private(set) var completedTiles = 0
  private var nextTile = 0
  private var current: Tile?

  init(
    source: CGImage, factor: Int, overlap: TileOverlap, settings: TUSettings, loraWeight: Double, trigger: String,
    preset: TUPreset, tempFolder: URL
  ) {
    self.overlap = overlap
    self.settings = settings.clamped(overlap: overlap)
    self.source = source
    self.factor = factor
    self.scaled = TileGrid.scaledSize(width: source.width, height: source.height, factor: factor)
    self.plan = TileGrid.plan(width: scaled.width, height: scaled.height, overlap: overlap, free: self.settings.free, tile: self.settings.tile)
    let shown = TUPreview.size(width: scaled.width, height: scaled.height)
    self.previewScale = Double(shown.width) / Double(scaled.width)
    self.previewCanvas = TUCanvas(width: shown.width, height: shown.height)
    self.loraWeight = loraWeight
    self.trigger = trigger
    self.preset = preset
    self.tempFolder = tempFolder
  }

  /// The answer to a `session.next`: the pass for the next tile, or `{"done":true}`.
  func next(_ request: TUNextRequest) -> Data {
    if canvas == nil { canvas = TUCanvas(scaling: source, factor: factor, size: scaled) }
    if baseCanvas == nil, settings.fade > 0 { baseCanvas = TUCanvas(scaling: source, factor: factor, size: scaled) }
    guard let canvas else {
      problem = "the picture is too big to work on"
      return TUMessages.done
    }
    // The result of the tile that was running goes back where it came from.
    if let tile = current, let previous = request.previous {
      guard previous.width == tile.rect.width, previous.height == tile.rect.height,
        let result = TUImage.load(URL(fileURLWithPath: previous.path)),
        result.width == tile.rect.width, result.height == tile.rect.height
      else {
        problem = "the result of tile \(Self.name(of: tile)) does not fit its tile"
        return TUMessages.done
      }
      canvas.paste(result, at: tile.rect)
      previewCanvas?.draw(result, in: TUPreview.rect(of: tile.rect, scale: previewScale))
      completedTiles += 1
    }
    current = nil
    guard nextTile < plan.count else { return TUMessages.done }
    let tile = plan.tiles[nextTile]
    nextTile += 1
    current = tile
    guard var piece = canvas.crop(tile.rect) else {
      problem = "tile \(Self.name(of: tile)) could not be cut"
      return TUMessages.done
    }
    // The edge between what the neighbours made and the source is faded, so the model does not read it as part of the picture.
    if settings.fade > 0, tile.row > 0 || tile.column > 0, let base = baseCanvas?.crop(tile.rect),
      let faded = TUFade.apply(
        canvas: piece, base: base, column: tile.column, row: tile.row, overlap: overlap.rawValue, fade: settings.fade)
    {
      piece = faded
    }
    guard let png = TUImage.pngData(piece) else {
      problem = "tile \(Self.name(of: tile)) could not be cut"
      return TUMessages.done
    }
    let tileURL = tempFolder.appendingPathComponent("tile-\(tile.index).png")
    var answer: [String: Any] = [
      "title": "Tile \(Self.name(of: tile))", "startImage": ["path": tileURL.path, "name": "tile-\(tile.index)"],
      "size": ["width": tile.rect.width, "height": tile.rect.height], "preset": preset.name,
      "fields": preset.fields(prompt: TUPrompt.text(trigger: trigger)), "loras": preset.loras(weight: loraWeight),
      "strength": preset.strength,
    ]
    do {
      try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
      try png.write(to: tileURL)
      if let masked = tile.maskRect {
        let maskURL = tempFolder.appendingPathComponent("mask-\(tile.index).png")
        guard let maskPNG = TUImage.maskPNG(width: tile.rect.width, height: tile.rect.height, masked: masked) else {
          throw CocoaError(.fileWriteUnknown)
        }
        try maskPNG.write(to: maskURL)
        answer["mask"] = ["path": maskURL.path, "name": "mask-\(tile.index)"]
        answer["maskSettings"] = [
          "blur": settings.blur, "outset": settings.outset, "preserveOriginal": true,
        ]
      }
    } catch {
      problem = "the files of tile \(Self.name(of: tile)) could not be written"
      return TUMessages.done
    }
    return (try? JSONSerialization.data(withJSONObject: answer)) ?? TUMessages.done
  }

  /// The tiles that are back, at full opacity and in their places, on a transparent picture of the final ratio (at most
  /// 1200 px on the long side); where a tile is not back yet it is transparent.
  func previewImage() -> CGImage? { previewCanvas?.image() }

  /// The session is over. The composed picture when it finished with no problem, else nil.
  func end(_ reason: String) -> CGImage? {
    let result = reason == "finished" && problem == nil ? canvas?.image() : nil
    canvas = nil
    baseCanvas = nil
    current = nil
    return result
  }

  /// "1A": the row number and the column letter.
  static func name(of tile: Tile) -> String {
    let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    let column = tile.column < letters.count ? String(letters[tile.column]) : "#\(tile.column + 1)"
    return "\(tile.row + 1)\(column)"
  }
}
