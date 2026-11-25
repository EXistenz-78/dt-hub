import Foundation

/// What the plug-in remembers for a project: the mode and the view.
struct SPSession: Codable, Equatable {
  var mode: SPMode = .both
  var view: SPView = .tile
}

/// `state.json` in the folder the app gives the plug-in for the open project; nothing is read or written before the app
/// says which project is open.
struct SPStore {
  static let fileName = "state.json"

  var folder: URL?

  private var fileURL: URL? { folder?.appendingPathComponent(Self.fileName) }

  func save(_ session: SPSession) {
    guard let fileURL, let data = try? JSONEncoder().encode(session) else { return }
    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }

  /// The saved session; nil when there is none or it cannot be read.
  func load() -> SPSession? {
    guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(SPSession.self, from: data)
  }
}
