import Foundation

/// What the plug-in remembers for a project: the three choices of the tab, in `state.json` of the folder the app gave
/// the plug-in for the project. Before the app says which project is open there is nothing to read or write.
struct TUChoice: Codable, Equatable, Sendable {
  var factor: Int
  var overlap: Int
  var loraWeight: Double

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
    return choice
  }

  func save(_ choice: TUChoice) {
    guard let fileURL, let data = try? JSONEncoder().encode(choice) else { return }
    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }
}
