import Foundation

/// I dati con cui lavora il tab.
struct F3Data {
  var database: PromptDatabase
  var config: F3Config
  var warnings: [DataWarning]

  static let databaseFileName = "prompt-database.json"
  static let configFileName = "flux3.json"
  static let pluginFolderName = "prompt-master"

  /// Le copie incorporate nel plug-in. Una rotta è un errore della build, preso dai test.
  static let embeddedDatabase: PromptDatabase = decode(EmbeddedVocabulary.database)
  static let embeddedConfig: F3Config = decode(EmbeddedData.flux3)

  private static func decode<T: Decodable>(_ text: String) -> T {
    do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) } catch { fatalError("Embedded data: \(error)") }
  }

  static func load(folder: URL = DataSource.defaultFolder) -> F3Data {
    let database = DataSource.load(
      PromptDatabase.self, fileURL: folder.appendingPathComponent(databaseFileName), embedded: embeddedDatabase)
    let config = DataSource.load(
      F3Config.self,
      fileURL: folder.appendingPathComponent(pluginFolderName).appendingPathComponent(configFileName),
      embedded: embeddedConfig)
    return F3Data(
      database: database.value, config: config.value, warnings: [database.warning, config.warning].compactMap { $0 })
  }
}
