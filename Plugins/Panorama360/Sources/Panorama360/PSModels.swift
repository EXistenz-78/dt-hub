import Foundation

/// One picture placed on the panorama. The angles are in degrees; `file` is relative to the project folder.
struct Sticker: Codable, Equatable, Hashable, Identifiable, Sendable {
  var id = UUID()
  var name: String
  var file: String
  var yaw = 0.0
  var pitch = 0.0
  var rot = 0.0
  /// The horizontal field of view; the vertical one comes from the picture's proportions and is never stored.
  var hfov = 60.0
  var opacity = 1.0
  var visible = true

  /// Brings every value into its range: angles into (−180, 180], pitch to ±89°, field of view to 5…170°, opacity to 0…1.
  mutating func clampValues() {
    yaw = PSProjection.wrapYaw(yaw)
    rot = PSProjection.wrapYaw(rot)
    pitch = min(89, max(-89, pitch))
    hfov = min(170, max(5, hfov))
    opacity = min(1, max(0, opacity))
  }
}

/// Normal runs the preset without the refiner, Fast the one with it.
enum PanoMode: String, Codable, Sendable { case normal, fast }

/// What the plug-in remembers for a project (`state.json`). The order of `stickers` is the order of the layers: the last one is on top.
struct PanoState: Codable, Equatable, Sendable {
  static let currentVersion = 1
  static let fileName = "state.json"

  var version = PanoState.currentVersion
  var stickers: [Sticker] = []
  var selectedID: UUID?
  var description = ""
  var mode = PanoMode.normal
  var guides = true

  /// The file of the folder, or an empty state: a missing file is just empty; one that cannot be read, or that a newer plug-in wrote,
  /// is set aside as `state.json.bak` (replacing an older backup) and the state starts empty.
  static func load(from folder: URL) -> PanoState {
    let url = folder.appendingPathComponent(fileName)
    guard let data = try? Data(contentsOf: url) else { return PanoState() }
    if let state = try? JSONDecoder().decode(PanoState.self, from: data), state.version <= currentVersion { return state }
    let backup = folder.appendingPathComponent(fileName + ".bak")
    try? FileManager.default.removeItem(at: backup)
    try? FileManager.default.moveItem(at: url, to: backup)
    return PanoState()
  }

  func save(to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try encoder.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
  }
}
