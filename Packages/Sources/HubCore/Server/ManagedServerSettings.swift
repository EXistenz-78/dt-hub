import Foundation

/// How DT Hub reaches Draw Things (spec §5): a server already running, or one DT Hub starts.
public enum ServerMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case attach
  case managed

  public var id: String { rawValue }
}

/// What the file system says, so the checks below can be tested without touching disk.
public struct FileSystemProbe: Sendable {
  public var isExecutableFile: @Sendable (String) -> Bool
  public var isDirectory: @Sendable (String) -> Bool
  /// Whether the folder holds at least one model file (`.ckpt`, Draw Things' format).
  public var hasModelFiles: @Sendable (String) -> Bool

  public init(
    isExecutableFile: @escaping @Sendable (String) -> Bool, isDirectory: @escaping @Sendable (String) -> Bool,
    hasModelFiles: @escaping @Sendable (String) -> Bool = { _ in true }
  ) {
    self.isExecutableFile = isExecutableFile
    self.isDirectory = isDirectory
    self.hasModelFiles = hasModelFiles
  }

  public static let live = FileSystemProbe(
    isExecutableFile: { FileManager.default.isExecutableFile(atPath: $0) },
    isDirectory: {
      var isDirectory: ObjCBool = false
      return FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory) && isDirectory.boolValue
    },
    hasModelFiles: { folder in
      let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
      return names.contains { $0.hasSuffix(".ckpt") }
    })
}

/// The gRPCServerCLI DT Hub starts (spec §5, "Avvia gRPCServerCLI"): where the program is, the
/// models folder, and the port. The server only ever listens on this Mac (127.0.0.1).
public struct ManagedServerSettings: Equatable, Codable, Sendable {
  public var mode: ServerMode
  public var binaryPath: String
  public var modelsFolder: String
  public var port: Int

  /// 7860, next to the Draw Things app's own API server on 7859.
  public static let defaultPort = 7860

  public init(
    mode: ServerMode = .attach, binaryPath: String = "", modelsFolder: String = "", port: Int = defaultPort
  ) {
    self.mode = mode
    self.binaryPath = binaryPath
    self.modelsFolder = modelsFolder
    self.port = port
  }

  public static let `default` = ManagedServerSettings()

  public enum ValidationError: Equatable, Sendable {
    case noBinary
    case binaryNotExecutable
    case noModelsFolder
    case modelsFolderMissing
    case invalidPort
  }

  /// Why the server cannot be started with these settings, or nil when it can.
  public func validationError(_ files: FileSystemProbe = .live) -> ValidationError? {
    let binary = binaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    let folder = modelsFolder.trimmingCharacters(in: .whitespacesAndNewlines)
    if binary.isEmpty { return .noBinary }
    if !files.isExecutableFile(binary) { return .binaryNotExecutable }
    if folder.isEmpty { return .noModelsFolder }
    if !files.isDirectory(folder) { return .modelsFolderMissing }
    if !(1024...65535).contains(port) { return .invalidPort }
    return nil
  }

  public enum Warning: Equatable, Sendable {
    /// The folder exists but holds no `.ckpt` file: the server would list no models. The
    /// Draw Things app may keep its models elsewhere (an external disk, for instance).
    case noModelFiles
  }

  /// Something worth saying about settings that can be used, or nil.
  public func warning(_ files: FileSystemProbe = .live) -> Warning? {
    guard validationError(files) == nil else { return nil }
    return files.hasModelFiles(modelsFolder.trimmingCharacters(in: .whitespacesAndNewlines)) ? nil : .noModelFiles
  }

  /// Lenient: a missing or unreadable field takes its default.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    mode = value(.mode, .attach)
    binaryPath = value(.binaryPath, "")
    modelsFolder = value(.modelsFolder, "")
    port = value(.port, Self.defaultPort)
  }
}

/// Persists `ManagedServerSettings` in UserDefaults as JSON (spec §11).
public struct ManagedServerSettingsStore {
  private let defaults: UserDefaults
  static let key = "drawThings.managedServer"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func load() -> ManagedServerSettings {
    guard let data = defaults.data(forKey: Self.key),
      let settings = try? JSONDecoder().decode(ManagedServerSettings.self, from: data)
    else { return .default }
    return settings
  }

  public func save(_ settings: ManagedServerSettings) {
    defaults.set(try? JSONEncoder().encode(settings), forKey: Self.key)
  }
}

/// Where gRPCServerCLI may already be installed, in the order they are tried.
public enum CLILocator {
  public static let fileName = "gRPCServerCLI-macOS"

  public static func candidatePaths(home: String = NSHomeDirectory()) -> [String] {
    [
      "\(home)/Applications/DrawThings-CLI/\(fileName)",
      "\(home)/Applications/\(fileName)",
      "/opt/homebrew/bin/\(fileName)",
      "/usr/local/bin/\(fileName)",
      "/opt/homebrew/bin/gRPCServerCLI",
      "/usr/local/bin/gRPCServerCLI",
    ]
  }

  /// The first candidate that is an executable file, nil when none is.
  public static func find(
    home: String = NSHomeDirectory(), files: FileSystemProbe = .live
  ) -> String? {
    candidatePaths(home: home).first { files.isExecutableFile($0) }
  }

  /// The models folder of the Draw Things app, offered by a button (reading it asks the user
  /// for permission the first time, so DT Hub never looks at it unprompted).
  public static func drawThingsAppModelsFolder(home: String = NSHomeDirectory()) -> String {
    "\(home)/Library/Containers/com.liuliu.draw-things/Data/Documents/Models"
  }
}

/// The command line of the managed server (spec §5).
public enum ServerArguments {
  /// The models folder first, then: `--address 127.0.0.1` (the program's default,
  /// `0.0.0.0`, would offer the server to the whole network), the port, and `--model-browser`
  /// (without it DT Hub cannot list the models). No shared secret: on the command line any
  /// program could read it, and the server is not reachable from outside.
  public static func make(_ settings: ManagedServerSettings) -> [String] {
    [
      settings.modelsFolder.trimmingCharacters(in: .whitespacesAndNewlines),
      "--address", "127.0.0.1",
      "--port", String(settings.port),
      "--model-browser",
    ]
  }
}
