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

  static let standard = TUSettings(free: 200, blur: 30, outset: 30, fade: 48)
  static let blurRange = 0.0...30.0
  static let outsetRange = 0...100

  /// What the masks leave free by default: 25/32 of the overlap (200 of 256, 250 of 320).
  static func defaultFree(for overlap: TileOverlap) -> Int { Int((Double(overlap.rawValue) * 25 / 32).rounded()) }

  /// Every value in its range; the fade stays in what the free part leaves of the overlap (the part that is regenerated:
  /// the free part is put back as it was sent, so a fade there would end up in the picture).
  func clamped(overlap: TileOverlap) -> TUSettings {
    let free = min(max(free, 0), overlap.rawValue)
    return TUSettings(
      free: free, blur: min(max(blur, Self.blurRange.lowerBound), Self.blurRange.upperBound),
      outset: min(max(outset, Self.outsetRange.lowerBound), Self.outsetRange.upperBound),
      fade: min(max(fade, 0), overlap.rawValue - free))
  }
}

struct TUChoice: Codable, Equatable, Sendable {
  var factor: Int
  var overlap: Int
  var loraWeight: Double
  var settings: TUSettings

  init(factor: Int, overlap: Int, loraWeight: Double, settings: TUSettings = .standard) {
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
    settings = (try? container.decodeIfPresent(TUSettings.self, forKey: .settings)) ?? .standard
  }

  static let standard = TUChoice(factor: 2, overlap: TileOverlap.standard.rawValue, loraWeight: 1)
}

struct TUStore {
  static let fileName = "state.json"

  /// The plug-in's folder in the open project; nil until the app sends the first `project` message.
  var folder: URL?

  private var fileURL: URL? { folder?.appendingPathComponent(Self.fileName) }

  func load() -> TUChoice {
    guard let fileURL, let data = try? Data(contentsOf: fileURL),
      var choice = try? JSONDecoder().decode(TUChoice.self, from: data), [2, 4, 8].contains(choice.factor),
      TileOverlap(rawValue: choice.overlap) != nil
    else { return .standard }
    let range = TUPresetTable.loraWeightRange
    choice.loraWeight = min(max(choice.loraWeight, range.lowerBound), range.upperBound)
    choice.settings = choice.settings.clamped(overlap: TileOverlap(rawValue: choice.overlap) ?? .standard)
    return choice
  }

  func save(_ choice: TUChoice) {
    guard let fileURL, let data = try? JSONEncoder().encode(choice) else { return }
    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }
}
