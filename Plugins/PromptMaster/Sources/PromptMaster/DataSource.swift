import Foundation

/// Both data files say which layout they have and which edition.
protocol VersionedData {
  var schema: Int { get }
  var version: String { get }
  /// No id is used twice: a list built from the file would crash on a repeated one.
  var hasUniqueIDs: Bool { get }
}

extension VersionedData {
  var hasUniqueIDs: Bool { true }
}

/// Why a file in the data folder was not used.
enum DataWarning: Equatable, Sendable {
  case unreadable(file: String)
  case unknownSchema(file: String)
  /// An id is used twice (a hand-edited file): the list and the Shuffle could not work with it.
  case repeatedIDs(file: String)
}

struct LoadedData<T> {
  var value: T
  var fromFile: Bool
  var warning: DataWarning?
}

/// Where the data files live and which copy wins (spec §3): the file in the folder, unless it is missing, unreadable,
/// of a layout this plug-in does not know, or older than the copy built into the plug-in.
enum DataSource {
  static let supportedSchema = 1

  static var defaultFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true).appendingPathComponent("Data", isDirectory: true)
  }

  /// `a` is an older edition than `b`: dotted numbers compared one by one (2.10.0 is newer than 2.9.0); a missing or
  /// unreadable part counts as 0.
  static func isOlder(_ a: String, than b: String) -> Bool {
    let left = a.split(separator: ".").map { Int($0) ?? 0 }
    let right = b.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(left.count, right.count) {
      let (x, y) = (index < left.count ? left[index] : 0, index < right.count ? right[index] : 0)
      if x != y { return x < y }
    }
    return false
  }

  static func load<T: Decodable & VersionedData>(_ type: T.Type, fileURL: URL, embedded: T) -> LoadedData<T> {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return LoadedData(value: embedded, fromFile: false) }
    let name = fileURL.lastPathComponent
    guard let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(T.self, from: data) else {
      return LoadedData(value: embedded, fromFile: false, warning: .unreadable(file: name))
    }
    guard file.schema == supportedSchema else {
      return LoadedData(value: embedded, fromFile: false, warning: .unknownSchema(file: name))
    }
    guard file.hasUniqueIDs else {
      return LoadedData(value: embedded, fromFile: false, warning: .repeatedIDs(file: name))
    }
    if isOlder(file.version, than: embedded.version) { return LoadedData(value: embedded, fromFile: false) }
    return LoadedData(value: file, fromFile: true)
  }
}

/// The data the tab works with.
struct PMData {
  var database: PromptDatabase
  var masters: MasterPrompts
  var warnings: [DataWarning]

  static let databaseFileName = "prompt-database.json"
  static let mastersFileName = "master-prompts.json"
  static let pluginFolderName = "prompt-master"

  /// The copies built into the plug-in. A broken one is a bug of the build, caught by the tests.
  static let embeddedDatabase: PromptDatabase = decode(EmbeddedData.database)
  static let embeddedMasters: MasterPrompts = decode(EmbeddedData.masterPrompts)

  private static func decode<T: Decodable>(_ text: String) -> T {
    do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) } catch { fatalError("Embedded data: \(error)") }
  }

  static func load(folder: URL = DataSource.defaultFolder) -> PMData {
    let database = DataSource.load(
      PromptDatabase.self, fileURL: folder.appendingPathComponent(databaseFileName), embedded: embeddedDatabase)
    let masters = DataSource.load(
      MasterPrompts.self,
      fileURL: folder.appendingPathComponent(pluginFolderName).appendingPathComponent(mastersFileName),
      embedded: embeddedMasters)
    return PMData(
      database: database.value, masters: masters.value, warnings: [database.warning, masters.warning].compactMap { $0 })
  }
}
