import Foundation

/// `moss.json`: le categorie nascoste, quelle solo-Foto e solo-Arte, quelle che vanno in `meta`, i termini aggiunti al
/// negativo, le opzioni dell'LLM. Il master prompt è un file Markdown a parte (`MossPrompts`).
struct MossConfig: Codable, Equatable, Sendable, VersionedData {
  var schema: Int
  var version: String
  var hiddenCategories: [String]
  var photoOnly: [String]
  var artOnly: [String]
  var metaCategories: [String]
  var extraNegativeTerms: [PMTerm]
  var options: LLMSettings
}

/// I dati con cui lavora il tab.
struct MossData {
  var database: PromptDatabase
  var config: MossConfig
  var warnings: [DataWarning]

  static let databaseFileName = "prompt-database.json"
  static let configFileName = "moss.json"
  static let pluginFolderName = "prompt-master"

  /// Le copie incorporate nel plug-in. Una rotta è un errore della build, preso dai test.
  static let embeddedDatabase: PromptDatabase = decode(EmbeddedVocabulary.database)
  static let embeddedConfig: MossConfig = decode(EmbeddedData.moss)

  private static func decode<T: Decodable>(_ text: String) -> T {
    do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) } catch { fatalError("Embedded data: \(error)") }
  }

  static func load(folder: URL = DataSource.defaultFolder) -> MossData {
    let database = DataSource.load(
      PromptDatabase.self, fileURL: folder.appendingPathComponent(databaseFileName), embedded: embeddedDatabase)
    let config = DataSource.load(
      MossConfig.self,
      fileURL: folder.appendingPathComponent(pluginFolderName).appendingPathComponent(configFileName),
      embedded: embeddedConfig)
    return MossData(
      database: database.value, config: config.value, warnings: [database.warning, config.warning].compactMap { $0 })
  }
}
