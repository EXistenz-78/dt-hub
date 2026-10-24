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
  private(set) var loraWeight: Double
  private let trigger: String
  /// The user's own instructions, added to the preset's prompt of every tile.
  /// Read at every tile, so a change made while the pipeline waits or runs reaches the next tile.
  var extraPrompt: String
  let preset: TUPreset
  /// The folder of the app's presets: the preset file is read at every tile (the user may change it meanwhile). Nil: the table only.
  private let presetFolder: URL?
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
  /// One past the last tile this run makes: all of them, or the one being regenerated.
  private var lastTile: Int
  private var current: Tile?
  /// The tile being regenerated after the run, nil during the run itself.
  private var regenerating: Int?
  /// True once a run finished with no problem: the canvas is whole and a tile can be made again.
  private(set) var isComplete = false

  init(
    source: CGImage, factor: Int, overlap: TileOverlap, settings: TUSettings, loraWeight: Double, trigger: String,
    extraPrompt: String = "", preset: TUPreset, presetFolder: URL? = nil, tempFolder: URL
  ) {
    self.extraPrompt = extraPrompt
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
    self.presetFolder = presetFolder
    self.tempFolder = tempFolder
    self.lastTile = plan.count
  }

  /// The prompt of every tile: the preset's, then the user's instructions.
  var prompt: String { TUPrompt.compose(preset.prompt(trigger: trigger), extra: extraPrompt) }

  /// The preset as the user has it now.
  var presetFile: TUPresetFile? { TUPresetFile.read(named: preset.name, in: presetFolder) }

  /// Makes the next run a single tile of the finished picture: it starts from the original, not from the result that is there.
  /// False when there is no finished picture or no such tile.
  func beginRegeneration(of index: Int, loraWeight: Double, extraPrompt: String) -> Bool {
    guard isComplete, canvas != nil, plan.tiles.indices.contains(index) else { return false }
    self.loraWeight = loraWeight
    self.extraPrompt = extraPrompt
    regenerating = index
    nextTile = index
    lastTile = index + 1
    current = nil
    problem = nil
    return true
  }

  /// The tile made again is given up before it started (the app did not take the pipeline): the picture stays as it was.
  func cancelRegeneration() {
    regenerating = nil
    lastTile = plan.count
    current = nil
  }

  /// The answer to a `session.next`: the pass for the next tile, or `{"done":true}`.
  func next(_ request: TUNextRequest) -> Data {
    if canvas == nil { canvas = TUCanvas(scaling: source, factor: factor, size: scaled) }
    if baseCanvas == nil, regenerating != nil || settings.fade > 0 || settings.toneStrength > 0 {
      baseCanvas = TUCanvas(scaling: source, factor: factor, size: scaled)
    }
    guard let canvas else {
      problem = "the picture is too big to work on"
      return TUMessages.done
    }
    // The result of the tile that was running goes back where it came from.
    if let previous = request.previous, !absorb(previous) { return TUMessages.done }
    current = nil
    guard nextTile < lastTile else { return TUMessages.done }
    let tile = plan.tiles[nextTile]
    nextTile += 1
    current = tile
    guard var piece = (regenerating != nil ? regenerationPiece(for: tile) : canvas.crop(tile.rect)) else {
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
    let file = presetFile
    var answer: [String: Any] = [
      "title": "Tile \(Self.name(of: tile))", "startImage": ["path": tileURL.path, "name": "tile-\(tile.index)"],
      "size": ["width": tile.rect.width, "height": tile.rect.height], "preset": preset.name,
      "fields": preset.passFields(extra: extraPrompt, file: file), "loras": preset.passLoras(weight: loraWeight, file: file),
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

  /// The result of the tile that was running goes back where it came from (its tone brought back to the source's first, so the
  /// next tile finds its neighbour right). False when the result does not fit its tile.
  private func absorb(_ previous: TUNextRequest.Previous) -> Bool {
    guard let tile = current, let canvas else { return true }
    guard previous.width == tile.rect.width, previous.height == tile.rect.height,
      let result = TUImage.load(URL(fileURLWithPath: previous.path)),
      result.width == tile.rect.width, result.height == tile.rect.height
    else {
      problem = "the result of tile \(Self.name(of: tile)) does not fit its tile"
      return false
    }
    var composed = result
    if settings.toneStrength > 0, let base = baseCanvas?.crop(tile.rect),
      let corrected = TUTone.correct(
        result: result, base: base, maskRect: tile.maskRect, radius: settings.toneRadius,
        strength: Double(settings.toneStrength) / 100)
    {
      composed = corrected
    }
    canvas.paste(composed, at: tile.rect)
    previewCanvas?.draw(composed, in: TUPreview.rect(of: tile.rect, scale: previewScale))
    if regenerating == nil { completedTiles += 1 }
    current = nil
    return true
  }

  /// The input of a tile made again: the original there, but the strips it shares with the tiles above and to the left are what
  /// those tiles made (as they were when the run reached this tile), so the join is kept.
  private func regenerationPiece(for tile: Tile) -> CGImage? {
    guard let canvas, let base = baseCanvas, let original = base.crop(tile.rect) else { return nil }
    guard tile.row > 0 || tile.column > 0, let work = TUCanvas(width: tile.rect.width, height: tile.rect.height) else {
      return original
    }
    work.paste(original, at: TileRect(x: 0, y: 0, width: tile.rect.width, height: tile.rect.height))
    let strip = overlap.rawValue
    if tile.row > 0 {
      let height = min(strip, tile.rect.height)
      if let top = canvas.crop(TileRect(x: tile.rect.x, y: tile.rect.y, width: tile.rect.width, height: height)) {
        work.paste(top, at: TileRect(x: 0, y: 0, width: tile.rect.width, height: height))
      }
    }
    if tile.column > 0 {
      let width = min(strip, tile.rect.width)
      if let left = canvas.crop(TileRect(x: tile.rect.x, y: tile.rect.y, width: width, height: tile.rect.height)) {
        work.paste(left, at: TileRect(x: 0, y: 0, width: width, height: tile.rect.height))
      }
    }
    return work.image()
  }

  /// The session is over. `previous` is the result of the last pass when the app sends it with the closing message (it does not
  /// ask again after the last pass). The composed picture when the run finished with no problem, else nil. A finished picture is
  /// kept, so a tile can be made again; a run that did not finish drops it, a tile made again that did not finish leaves it as it was.
  func end(_ reason: String, previous: TUNextRequest.Previous? = nil) -> CGImage? {
    if reason == "finished", let previous { _ = absorb(previous) }
    let succeeded = reason == "finished" && problem == nil
    let wasRegenerating = regenerating != nil
    regenerating = nil
    current = nil
    if succeeded {
      isComplete = true
      lastTile = plan.count
      return canvas?.image()
    }
    if !wasRegenerating {
      canvas = nil
      baseCanvas = nil
      isComplete = false
    } else {
      lastTile = plan.count
    }
    return nil
  }

  /// "1A": the row number and the column letter.
  static func name(of tile: Tile) -> String {
    let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    let column = tile.column < letters.count ? String(letters[tile.column]) : "#\(tile.column + 1)"
    return "\(tile.row + 1)\(column)"
  }
}
