import Foundation
import HubKit

/// What the Generation tab shows, restored at the next launch (spec §11).
public struct SessionSnapshot: Equatable, Codable, Sendable {
  public var prompt: String
  public var negativePrompt: String
  public var parameters: GenerationParameters
  public var lockRatio: Bool

  public init(prompt: String = "", negativePrompt: String = "", parameters: GenerationParameters = .default, lockRatio: Bool = false) {
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.parameters = parameters
    self.lockRatio = lockRatio
  }

  /// Lenient: a missing field takes its default (parameters decode leniently too).
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    prompt = (try? container.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
    negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
    parameters = (try? container.decodeIfPresent(GenerationParameters.self, forKey: .parameters)) ?? .default
    lockRatio = (try? container.decodeIfPresent(Bool.self, forKey: .lockRatio)) ?? false
  }
}

/// Reads and writes the session as JSON in the app's support folder (spec §11).
public struct SessionStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  /// ~/Library/Application Support/DT Hub/session.json.
  public static var defaultFileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("session.json")
  }

  /// nil when there is no session yet or the file cannot be read: the tab starts from defaults.
  public func load() -> SessionSnapshot? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
  }

  public func save(_ snapshot: SessionSnapshot) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
  }
}
