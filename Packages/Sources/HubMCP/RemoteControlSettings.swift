import Foundation

/// The "Remote control" settings (spec §6). Off by default; read from storage leniently.
public struct RemoteControlSettings: Codable, Equatable, Sendable {
  public var enabled = false
  public var port: UInt16 = 8765
  public var mode: AccessMode = .readOnly
  /// A single request above this many images asks for confirmation until the user has authorised the session.
  public var confirmThreshold = 20
  /// Images the agent may make in one session; always enforced.
  public var imageBudget = 200
  /// Compute units (DT+ cloud) the agent may use in one session; nil = no limit.
  public var cuBudget: Int?
  /// How long a confirmation waits for the user before it is refused. Not a limit on a generation.
  public var confirmTimeoutSeconds = 60
  /// Extra folders (besides the project, output and Results) an agent may read pictures from.
  public var allowedFolders: [String] = []

  public init() {}

  public func clamped() -> RemoteControlSettings {
    var copy = self
    copy.confirmThreshold = max(1, confirmThreshold)
    copy.imageBudget = max(1, imageBudget)
    copy.cuBudget = cuBudget.map { max(1, $0) }
    copy.confirmTimeoutSeconds = min(max(confirmTimeoutSeconds, 5), 600)
    return copy
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = RemoteControlSettings()
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    enabled = value(.enabled, d.enabled)
    port = value(.port, d.port)
    mode = value(.mode, d.mode)
    confirmThreshold = value(.confirmThreshold, d.confirmThreshold)
    imageBudget = value(.imageBudget, d.imageBudget)
    cuBudget = (try? c.decodeIfPresent(Int.self, forKey: .cuBudget)) ?? nil
    confirmTimeoutSeconds = value(.confirmTimeoutSeconds, d.confirmTimeoutSeconds)
    allowedFolders = value(.allowedFolders, d.allowedFolders)
  }
}

/// Persists `RemoteControlSettings` in UserDefaults as JSON.
public struct RemoteControlSettingsStore {
  static let key = "remoteControl.settings"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  public func load() -> RemoteControlSettings {
    guard let data = defaults.data(forKey: Self.key),
      let settings = try? JSONDecoder().decode(RemoteControlSettings.self, from: data)
    else { return RemoteControlSettings() }
    return settings.clamped()
  }

  public func save(_ settings: RemoteControlSettings) {
    defaults.set(try? JSONEncoder().encode(settings.clamped()), forKey: Self.key)
  }
}
