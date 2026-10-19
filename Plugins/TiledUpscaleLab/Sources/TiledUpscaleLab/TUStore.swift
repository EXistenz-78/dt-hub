import Foundation

/// What the plug-in remembers for a project: the three choices of the tab, in `state.json` of the folder the app gave
/// the plug-in for the project. Before the app says which project is open there is nothing to read or write.
/// The mask and the join (spec of the lab): how much of the overlap the masks leave free, how soft and how far the mask's
/// edge reaches (Draw Things' blur and outset), and how many pixels the neighbour's result is faded into the source.
struct TUSettings: Codable, Equatable, Sendable {
  var free: Int
  var blur: Double
  var outset: Int
  var fade: Int
  /// The longest side of a tile, in pixels: a multiple of 64 from 1024 to 2048. A bigger tile means fewer tiles and more of
  /// the picture in each, so the model has more to go on (a 4× enlargement goes from 25 passes at 1024 to 9 at 2048).
  var tile: Int
  /// How much of the correction of the tone is applied (0–100 %) and the radius, in pixels, of the blur that tells the slow drift
  /// of the level (corrected) from the detail (kept): see `TUTone`.
  var toneStrength: Int
  var toneRadius: Int

  init(free: Int, blur: Double, outset: Int, fade: Int, tile: Int = TileConstants.tile, toneStrength: Int = 0, toneRadius: Int = 64) {
    self.toneStrength = toneStrength
    self.toneRadius = toneRadius
    self.free = free
    self.blur = blur
    self.outset = outset
    self.fade = fade
    self.tile = tile
  }

  /// A file from before the tile size has none: 1024.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    free = try container.decode(Int.self, forKey: .free)
    blur = try container.decode(Double.self, forKey: .blur)
    outset = try container.decode(Int.self, forKey: .outset)
    fade = try container.decode(Int.self, forKey: .fade)
    tile = (try? container.decodeIfPresent(Int.self, forKey: .tile)) ?? TileConstants.tile
    toneStrength = (try? container.decodeIfPresent(Int.self, forKey: .toneStrength)) ?? Self.standard.toneStrength
    toneRadius = (try? container.decodeIfPresent(Int.self, forKey: .toneRadius)) ?? Self.standard.toneRadius
  }

  /// The values of the advanced section for an overlap (found by trying: 4× with tiles of about 1500 px). Only the free part
  /// depends on the overlap: all of it but the 64 px the fade needs.
  static func defaults(for overlap: TileOverlap) -> TUSettings {
    TUSettings(
      free: defaultFree(for: overlap), blur: 30, outset: 29, fade: 64, tile: TileConstants.tile, toneStrength: 100,
      toneRadius: 16)
  }

  static let standard = defaults(for: .standard)

  /// The tile for a picture: the smallest, a multiple of 64 between 1024 and 2048, that needs at most three tiles along the
  /// shorter side of the (cut) enlarged picture. Three tiles reach `3 × tile − 2 × overlap`.
  static func autoTile(shortestSide: Int, overlap: TileOverlap) -> Int {
    let wanted = (shortestSide + 2 * overlap.rawValue + 2) / 3
    let rounded = (wanted + 63) / 64 * 64
    return min(max(rounded, tileRange.lowerBound), tileRange.upperBound)
  }
  static let toneStrengthRange = 0...100
  static let toneRadiusRange = 16...256
  /// The enlargements the tab offers (8× went: too ambitious).
  static let factors = [2, 4]
  static let tileRange = 1024...2048
  static let blurRange = 0.0...30.0
  static let outsetRange = 0...100

  /// What the masks leave free by default: the overlap but the 64 px of the fade (192 of 256, 256 of 320).
  static func defaultFree(for overlap: TileOverlap) -> Int { overlap.rawValue - 64 }

  /// Every value in its range; the fade stays in what the free part leaves of the overlap (the part that is regenerated:
  /// the free part is put back as it was sent, so a fade there would end up in the picture).
  func clamped(overlap: TileOverlap) -> TUSettings {
    let free = min(max(free, 0), overlap.rawValue)
    return TUSettings(
      free: free, blur: min(max(blur, Self.blurRange.lowerBound), Self.blurRange.upperBound),
      outset: min(max(outset, Self.outsetRange.lowerBound), Self.outsetRange.upperBound),
      fade: min(max(fade, 0), overlap.rawValue - free),
      tile: min(max(tile, Self.tileRange.lowerBound), Self.tileRange.upperBound) / 64 * 64,
      toneStrength: min(max(toneStrength, Self.toneStrengthRange.lowerBound), Self.toneStrengthRange.upperBound),
      toneRadius: min(max(toneRadius, Self.toneRadiusRange.lowerBound), Self.toneRadiusRange.upperBound))
  }
}

struct TUChoice: Codable, Equatable, Sendable {
  var factor: Int
  var overlap: Int
  /// The LoRA strength of a project before the presets had one each; kept to read an old file (it becomes the FLUX preset's).
  var loraWeight: Double
  var settings: TUSettings
  /// The LoRA strength the user chose, by preset name ("" when the model has none); a preset without an entry has its own default.
  var loraWeights: [String: Double]

  init(factor: Int, overlap: Int, loraWeight: Double, settings: TUSettings = .standard, loraWeights: [String: Double] = [:]) {
    self.loraWeights = loraWeights
    self.factor = factor
    self.overlap = overlap
    self.loraWeight = loraWeight
    self.settings = settings
  }

  /// A file from before the settings has none: they take the defaults.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    factor = try container.decode(Int.self, forKey: .factor)
    overlap = try container.decode(Int.self, forKey: .overlap)
    loraWeight = try container.decode(Double.self, forKey: .loraWeight)
    loraWeights = (try? container.decodeIfPresent([String: Double].self, forKey: .loraWeights)) ?? [:]
    settings = (try? container.decodeIfPresent(TUSettings.self, forKey: .settings))
      ?? TUSettings.defaults(for: TileOverlap(rawValue: overlap) ?? .standard)
  }

  static let standard = TUChoice(factor: 2, overlap: TileOverlap.standard.rawValue, loraWeight: 1, settings: .standard)
}

struct TUStore {
  static let fileName = "state.json"

  /// The plug-in's folder in the open project; nil until the app sends the first `project` message.
  var folder: URL?

  private var fileURL: URL? { folder?.appendingPathComponent(Self.fileName) }

  func load() -> TUChoice {
    guard let fileURL, let data = try? Data(contentsOf: fileURL),
      var choice = try? JSONDecoder().decode(TUChoice.self, from: data),
      TileOverlap(rawValue: choice.overlap) != nil
    else { return .standard }
    // 8× is gone (too ambitious): a project that had it gets 4×.
    if choice.factor == 8 { choice.factor = 4 }
    guard TUSettings.factors.contains(choice.factor) else { return .standard }
    let range = TUPresetTable.loraWeightRange
    choice.loraWeight = min(max(choice.loraWeight, range.lowerBound), range.upperBound)
    // A project from before the presets had one strength each: it was the FLUX preset's (when the user had changed it).
    if choice.loraWeights.isEmpty, choice.loraWeight != 1 { choice.loraWeights[TUPresetTable.fluxKlein9BName] = choice.loraWeight }
    choice.loraWeights = choice.loraWeights.mapValues { min(max($0, range.lowerBound), range.upperBound) }
    choice.settings = choice.settings.clamped(overlap: TileOverlap(rawValue: choice.overlap) ?? .standard)
    return choice
  }

  func save(_ choice: TUChoice) {
    guard let fileURL, let data = try? JSONEncoder().encode(choice) else { return }
    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }
}
