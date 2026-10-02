import Foundation

/// One saved result in the history of the Results window: where its PNG is and when it was made.
public struct ResultsHistoryEntry: Codable, Equatable, Sendable {
  public let path: String
  public let date: Date

  public init(path: String, date: Date) {
    self.path = path
    self.date = date
  }
}

/// The strip of the Results window, kept across launches (`results.json`, spec §11): the paths of
/// the last results, newest first. The images stay where they were saved; the job of each one is
/// read back from its PNG.
public struct ResultsHistoryStore: Sendable {
  public static let limit = 50
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  /// ~/Library/Application Support/DT Hub/results.json.
  public static var defaultFileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("results.json")
  }

  /// A missing or unreadable file is an empty history.
  public func load() -> [ResultsHistoryEntry] {
    guard let data = try? Data(contentsOf: fileURL),
      let entries = try? JSONDecoder().decode([ResultsHistoryEntry].self, from: data)
    else { return [] }
    return Array(entries.prefix(Self.limit))
  }

  /// Writes the newest `limit` entries; a failure only loses the restore at the next launch.
  public func save(_ entries: [ResultsHistoryEntry]) {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(Array(entries.prefix(Self.limit))).write(to: fileURL, options: .atomic)
    } catch {
    }
  }
}
