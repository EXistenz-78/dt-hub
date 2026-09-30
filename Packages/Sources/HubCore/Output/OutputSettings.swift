import Foundation

/// The folder images are saved in (spec §7, Preferences › Output), kept in UserDefaults.
public struct OutputSettingsStore {
  private let defaults: UserDefaults
  static let key = "output.folder"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// ~/Pictures/DT Hub.
  public static var defaultFolder: URL {
    FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
  }

  public func folder() -> URL {
    guard let path = defaults.string(forKey: Self.key), !path.isEmpty else { return Self.defaultFolder }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  public func setFolder(_ url: URL) {
    defaults.set(url.path, forKey: Self.key)
  }
}
