import Foundation

/// Which plug-ins the user turned on (`plugins.json`). A plug-in just installed is off.
public struct PluginSettingsStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public static var defaultFileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true).appendingPathComponent("plugins.json")
  }

  private struct File: Codable {
    var enabled: [String]
  }

  /// A missing or unreadable file means nothing is on.
  public func enabled() -> Set<String> {
    guard let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(File.self, from: data)
    else { return [] }
    return Set(file.enabled)
  }

  public func save(_ identifiers: Set<String>) {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(File(enabled: identifiers.sorted())).write(to: fileURL, options: .atomic)
    } catch {
    }
  }
}
