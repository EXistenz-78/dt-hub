import Foundation

/// What the plug-in remembers: the choice of maps. Before DT Hub had projects it lived in `UserDefaults`; once the app
/// says which project is open (`folder`), it is `state.json` in the folder the app gave the plug-in for it.
struct DPStore {
  static let key = "com.exiztenz.dthub.depthpose.state.v1"
  static let fileName = "state.json"

  var defaults: UserDefaults = .standard
  /// The plug-in's folder in the open project; nil until the app sends the first `project` message.
  var folder: URL?

  private struct Saved: Codable { var mode: DPMode }

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
  func load() -> DPMode {
    read().flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }?.mode ?? .both
  }

  func save(_ mode: DPMode) {
    if let data = try? JSONEncoder().encode(Saved(mode: mode)) { write(data) }
  }

  /// The first project ever takes the state the tab had before projects: written to the file, only if there is none.
  func adoptLegacy() {
    guard let fileURL, !FileManager.default.fileExists(atPath: fileURL.path), let data = defaults.data(forKey: Self.key)
    else { return }
    write(data)
  }
}
