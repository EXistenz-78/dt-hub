import Foundation

/// What the tab remembers between runs: the text, the chosen terms, the Shuffle mode, the booru switch and which
/// groups and categories are open. The search is not kept.
struct PMSession: Codable, Equatable {
  var description = ""
  var selection: [String] = []
  var mode: StyleMode = .photo
  var booru = false
  var openGroups: [String] = []
  var openCategories: [String] = []
}

/// The session of the tab. Before DT Hub had projects it lived in `UserDefaults`, under a key of its own; once the
/// app says which project is open (`folder`), it is `state.json` in the folder the app gave the plug-in for it.
struct PMStore {
  static let key = "com.exiztenz.dthub.promptmaster.state.v1"
  static let fileName = "state.json"

  var defaults: UserDefaults = .standard
  var key: String = PMStore.key
  /// The plug-in's folder in the open project; nil until the app sends the first `project` message.
  var folder: URL?

  private var fileURL: URL? { folder?.appendingPathComponent(Self.fileName) }

  func save(_ session: PMSession) {
    guard let data = try? JSONEncoder().encode(session) else { return }
    if let fileURL {
      try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: fileURL, options: .atomic)
    } else {
      defaults.set(data, forKey: key)
    }
  }

  /// The saved session; a first run, a missing file, or one that cannot be read, starts empty.
  func load() -> PMSession {
    let data = fileURL.map { try? Data(contentsOf: $0) } ?? defaults.data(forKey: key)
    guard let data, let session = try? JSONDecoder().decode(PMSession.self, from: data) else { return PMSession() }
    return session
  }

  /// The first project ever takes the state the tab had before projects: written to the file, only if there is none.
  func adoptLegacy() {
    guard let fileURL, !FileManager.default.fileExists(atPath: fileURL.path), let data = defaults.data(forKey: key) else {
      return
    }
    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }
}
