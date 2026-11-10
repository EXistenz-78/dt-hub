import Foundation

/// The data the tab works with.
struct I4Data {
  var database: PromptDatabase
  var config: IdeogramConfig
  var warnings: [DataWarning]

  static let databaseFileName = "prompt-database.json"
  static let configFileName = "ideogram4.json"
  static let pluginFolderName = "prompt-master"

  /// The copies built into the plug-in. A broken one is a bug of the build, caught by the tests.
  static let embeddedDatabase: PromptDatabase = decode(EmbeddedVocabulary.database)
  static let embeddedConfig: IdeogramConfig = decode(EmbeddedData.ideogram4)

  private static func decode<T: Decodable>(_ text: String) -> T {
    do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) } catch { fatalError("Embedded data: \(error)") }
  }

  static func load(folder: URL = DataSource.defaultFolder) -> I4Data {
    let database = DataSource.load(
      PromptDatabase.self, fileURL: folder.appendingPathComponent(databaseFileName), embedded: embeddedDatabase)
    let config = DataSource.load(
      IdeogramConfig.self,
      fileURL: folder.appendingPathComponent(pluginFolderName).appendingPathComponent(configFileName),
      embedded: embeddedConfig)
    return I4Data(
      database: database.value, config: config.value, warnings: [database.warning, config.warning].compactMap { $0 })
  }
}
