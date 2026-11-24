import Foundation

/// `ming.json`: le categorie nascoste, quelle solo-Foto e solo-Arte, quelle della luce (vanno in `ambient_lighting`), le
/// opzioni dell'LLM. Il master prompt e il prompt di composizione sono file Markdown a parte (`MingPrompts`).
struct MingConfig: Codable, Equatable, Sendable, VersionedData {
  var schema: Int
  var version: String
  var hiddenCategories: [String]
  var photoOnly: [String]
  var artOnly: [String]
  var lightingCategories: [String]
  var options: LLMSettings
}

/// I dati con cui lavora il tab.
struct MingData {
  var database: PromptDatabase
  var config: MingConfig
  var warnings: [DataWarning]

  static let databaseFileName = "prompt-database.json"
  static let configFileName = "ming.json"
  static let pluginFolderName = "prompt-master"

  /// Le copie incorporate nel plug-in. Una rotta è un errore della build, preso dai test.
  static let embeddedDatabase: PromptDatabase = decode(EmbeddedVocabulary.database)
  static let embeddedConfig: MingConfig = decode(EmbeddedData.ming)

  private static func decode<T: Decodable>(_ text: String) -> T {
    do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) } catch { fatalError("Embedded data: \(error)") }
  }

  static func load(folder: URL = DataSource.defaultFolder) -> MingData {
    let database = DataSource.load(
      PromptDatabase.self, fileURL: folder.appendingPathComponent(databaseFileName), embedded: embeddedDatabase)
    let config = DataSource.load(
      MingConfig.self,
      fileURL: folder.appendingPathComponent(pluginFolderName).appendingPathComponent(configFileName),
      embedded: embeddedConfig)
    return MingData(
      database: database.value, config: config.value, warnings: [database.warning, config.warning].compactMap { $0 })
  }
}
