import Foundation

/// The data the tab works with.
struct PMData {
  var database: PromptDatabase
  var families: PMFamiliesData
  var warnings: [DataWarning]

  static let databaseFileName = "prompt-database.json"
  static let familiesFileName = "families.json"
  static let pluginFolderName = "prompt-master"

  /// The copies built into the plug-in. A broken one is a bug of the build, caught by the tests.
  static let embeddedDatabase: PromptDatabase = decode(EmbeddedVocabulary.database)
  static let embeddedFamilies: PMFamiliesData = decode(EmbeddedPrompts.families)

  private static func decode<T: Decodable>(_ text: String) -> T {
    do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) } catch { fatalError("Embedded data: \(error)") }
  }

  static func load(folder: URL = DataSource.defaultFolder) -> PMData {
    let database = DataSource.load(
      PromptDatabase.self, fileURL: folder.appendingPathComponent(databaseFileName), embedded: embeddedDatabase)
    let families = DataSource.load(
      PMFamiliesData.self,
      fileURL: folder.appendingPathComponent(pluginFolderName).appendingPathComponent(familiesFileName),
      embedded: embeddedFamilies)
    return PMData(
      database: database.value, families: families.value, warnings: [database.warning, families.warning].compactMap { $0 })
  }
}
