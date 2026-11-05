import Foundation

/// The user's own defaults per model (`~/Library/Application Support/DT Hub/recommended-overrides.json`): the same
/// file format as `RecommendedSettings.json`, with only the models the user saved. Missing or broken, it is empty;
/// written atomically, and a failed write only loses the change at the next launch.
public struct RecommendedOverridesStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public static var defaultFileURL: URL { CachedDownload.supportFile("recommended-overrides.json") }

  public func load() -> RecommendedSettings {
    guard let data = try? Data(contentsOf: fileURL) else { return .empty }
    return RecommendedSettings(data: data)
  }

  public func save(_ table: RecommendedSettings) {
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try table.encoded().write(to: fileURL, options: .atomic)
    } catch {
    }
  }
}
