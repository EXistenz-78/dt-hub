import Foundation
import HubKit

/// `loras.json` in the app's support folder: `{"schema": 1, "loras": {"<file>": {"trigger": "…", "weight": 0.8}}}`.
public struct LoRAOverridesStore: Sendable {
  public static let schema = 1
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  /// ~/Library/Application Support/DT Hub/loras.json.
  public static var defaultFileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("loras.json")
  }

  private struct File: Codable {
    var schema: Int
    var loras: [String: LoRAOverride]
  }

  /// A missing file, one that cannot be read or one of another layout is an empty list. Weights are brought into range.
  public func load() -> LoRAOverrides {
    guard let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(File.self, from: data),
      file.schema == Self.schema
    else { return LoRAOverrides() }
    var entries = file.loras
    for (name, entry) in entries {
      guard let weight = entry.weight else { continue }
      let range = LoRAOverrides.weightRange
      entries[name]?.weight = weight.isFinite ? min(max(weight, range.lowerBound), range.upperBound) : nil
    }
    return LoRAOverrides(entries: entries)
  }

  /// A failure only loses the change at the next launch.
  public func save(_ overrides: LoRAOverrides) {
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(File(schema: Self.schema, loras: overrides.entries)).write(to: fileURL, options: .atomic)
    } catch {
    }
  }
}
