import Foundation

/// Which maps the user wants: the two checkboxes of the tab.
struct DPSelection: Codable, Equatable, Sendable {
  var depth: Bool
  var pose: Bool

  static let both = DPSelection(depth: true, pose: true)

  init(depth: Bool, pose: Bool) {
    self.depth = depth
    self.pose = pose
  }

  /// Reads the two checkboxes, or the three-way choice (`"mode": depth | pose | both`) of the first version.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: Keys.self)
    if let depth = try container.decodeIfPresent(Bool.self, forKey: .depth),
      let pose = try container.decodeIfPresent(Bool.self, forKey: .pose)
    {
      self.init(depth: depth, pose: pose)
    } else {
      switch try container.decode(String.self, forKey: .mode) {
      case "depth": self.init(depth: true, pose: false)
      case "pose": self.init(depth: false, pose: true)
      default: self.init(depth: true, pose: true)
      }
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Keys.self)
    try container.encode(depth, forKey: .depth)
    try container.encode(pose, forKey: .pose)
  }

  private enum Keys: String, CodingKey { case depth, pose, mode }
}

/// What the plug-in remembers: the choice of maps. Before DT Hub had projects it lived in `UserDefaults`; once the app
/// says which project is open (`folder`), it is `state.json` in the folder the app gave the plug-in for it.
struct DPStore {
  static let key = "com.exiztenz.dthub.depthpose.state.v1"
  static let fileName = "state.json"

  var defaults: UserDefaults = .standard
  /// The plug-in's folder in the open project; nil until the app sends the first `project` message.
  var folder: URL?

  private var fileURL: URL? { folder?.appendingPathComponent(Self.fileName) }

  private func read() -> Data? {
    if let fileURL { return try? Data(contentsOf: fileURL) }
    return defaults.data(forKey: Self.key)
  }

  private func write(_ data: Data) {
    if let fileURL {
      try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: fileURL, options: .atomic)
    } else {
      defaults.set(data, forKey: Self.key)
    }
  }

  /// A missing or unreadable state is the first run: both maps.
  func load() -> DPSelection {
    read().flatMap { try? JSONDecoder().decode(DPSelection.self, from: $0) } ?? .both
  }

  func save(_ selection: DPSelection) {
    if let data = try? JSONEncoder().encode(selection) { write(data) }
  }

  /// The first project ever takes the state the tab had before projects: written to the file, only if there is none.
  func adoptLegacy() {
    guard let fileURL, !FileManager.default.fileExists(atPath: fileURL.path), let data = defaults.data(forKey: Self.key)
    else { return }
    write(data)
  }
}
