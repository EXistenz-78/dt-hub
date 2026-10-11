import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMaster

@Suite("The data files")
struct DataTests {
  // MARK: The copies built into the plug-in

  @Test func theEmbeddedDatabaseIsTheSlimOneWithEveryTerm() {
    let database = PMData.embeddedDatabase
    #expect(database.schema == DataSource.supportedSchema)
    #expect(database.groups.count == 8 && database.categories.count == 40)
    let terms = database.categories.flatMap(\.terms)
    #expect(terms.count == 875)
    #expect(Set(terms.map(\.id)).count == 875)  // ids are unique: a selection is a set of ids
    #expect(terms.allSatisfy { !$0.it.isEmpty && !$0.en.isEmpty })
    #expect(database.categories.allSatisfy { category in database.groups.contains { $0.id == category.group } })
    #expect(database.groups.first { $0.id == "H" }?.restricted == true)
    #expect(database.categories.filter { $0.negative == true }.map(\.id) == ["negative_terms"])
    // Slim: no booru or prose forms.
    #expect(!EmbeddedData.database.contains("en_tag") && !EmbeddedData.database.contains("en_prose"))
  }

  @Test func theEmbeddedFamilyDataCoversTheThirteenFamilies() {
    let data = PMData.embeddedFamilies
    #expect(Set(data.families.keys) == Set(PMFamilies.all))
    #expect(data.schema == DataSource.supportedSchema)
  }

  @Test func hiddenCategoriesAreRealOnesAndNegativeTermsAreHiddenWhereThereIsNoNegative() {
    let ids = Set(PMData.embeddedDatabase.categories.map(\.id))
    for (family, entry) in PMData.embeddedFamilies.families {
      #expect(Set(entry.hiddenCategories).isSubset(of: ids), Comment(rawValue: family))
      // Whether the family reads a negative prompt is the app's to say (Family prompt); here only the terms.
      let reads = Fixtures.appFamilies[family]?.negative == true
      if !reads { #expect(entry.hiddenCategories.contains("negative_terms"), Comment(rawValue: family)) }
    }
    #expect(PMData.embeddedFamilies.families["z_image"]?.hiddenCategories.contains("typography_text") == true)
    #expect(PMData.embeddedFamilies.families["qwen_image"]?.hiddenCategories == ["render_quality"])
    #expect(PMData.embeddedFamilies.families["cosmos2.5_2b"]?.hiddenCategories.count == 3)
  }

  @Test func onlyTheTwoFamiliesWithTheBooruSwitchHaveItsText() {
    for (family, entry) in PMData.embeddedFamilies.families {
      #expect((entry.booruSystem != nil) == PMFamilies.withBooruSwitch.contains(family), Comment(rawValue: family))
    }
  }

  @Test func theFourFamiliesWithoutAReviewAreMarkedProvisional() {
    let provisional = PMData.embeddedFamilies.families.filter { $0.value.provisional == true }.keys
    #expect(Set(provisional) == ["flux2", "qwen_image_2.1", "hidream_i1", "cosmos2.5_2b"])
  }

  @Test func theTwoRulesFilesAreValidAndAskForTheLabel() {
    for text in [EmbeddedPrompts.compose, EmbeddedPrompts.composeTags] {
      let file = DTHubPromptFile.parse(text)
      #expect(file.isValid && file.version == 1 && file.body.hasPrefix(#"You write prompts for the image model "{label}"."#))
    }
    #expect(EmbeddedPrompts.compose.contains("Enrich the description") && !EmbeddedPrompts.compose.contains("Do not add subjects"))
    #expect(EmbeddedPrompts.composeTags.contains("Do not add subjects") && !EmbeddedPrompts.composeTags.contains("Enrich the description"))
  }

  // MARK: Which copy wins

  private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pm-data-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url.appendingPathComponent("prompt-master"), withIntermediateDirectories: true)
    return url
  }

  private func databaseJSON(version: String, schema: Int = 1, marker: String = "X") -> Data {
    Data(
      """
      {"schema": \(schema), "version": "\(version)", "groups": [{"id": "A", "it": "\(marker)", "en": "\(marker)"}],
       "categories": []}
      """.utf8)
  }

  @Test func withoutAFileTheEmbeddedCopyIsUsedSilently() throws {
    let data = PMData.load(folder: try makeFolder())
    #expect(data.database == PMData.embeddedDatabase && data.families == PMData.embeddedFamilies && data.warnings.isEmpty)
  }

  @Test func aNewerFileWinsAndAnEqualOneToo() throws {
    let folder = try makeFolder()
    try databaseJSON(version: "99.0.0").write(to: folder.appendingPathComponent("prompt-database.json"))
    #expect(PMData.load(folder: folder).database.groups.first?.it == "X")
    try databaseJSON(version: PMData.embeddedDatabase.version).write(to: folder.appendingPathComponent("prompt-database.json"))
    #expect(PMData.load(folder: folder).database.groups.first?.it == "X")
  }

  @Test func anOlderFileLosesWithoutAWarning() throws {
    let folder = try makeFolder()
    try databaseJSON(version: "1.0.0").write(to: folder.appendingPathComponent("prompt-database.json"))
    let data = PMData.load(folder: folder)
    #expect(data.database == PMData.embeddedDatabase && data.warnings.isEmpty)
  }

  @Test func aFileOfAnUnknownLayoutOrGarbageLosesWithAWarningAndIsLeftAlone() throws {
    let folder = try makeFolder()
    let file = folder.appendingPathComponent("prompt-database.json")
    try databaseJSON(version: "99.0.0", schema: 2).write(to: file)
    #expect(PMData.load(folder: folder).warnings == [.unknownSchema(file: "prompt-database.json")])
    try Data("not json".utf8).write(to: file)
    let data = PMData.load(folder: folder)
    #expect(data.database == PMData.embeddedDatabase)
    #expect(data.warnings == [.unreadable(file: "prompt-database.json")])
    #expect(try Data(contentsOf: file) == Data("not json".utf8))  // never touched
  }

  @Test func aFileWithRepeatedIdsLosesWithAWarningAndIsLeftAloneBecauseTheListWouldCrash() throws {
    let folder = try makeFolder()
    let file = folder.appendingPathComponent("prompt-database.json")
    func write(_ json: String) throws { try Data(json.utf8).write(to: file) }
    let term = #"{"id": "t1", "it": "a", "en": "a"}"#
    // The same term id twice in one category, in two categories; the same category id twice; the same group twice.
    try write(#"{"schema": 1, "version": "99.0.0", "groups": [{"id": "A", "it": "x", "en": "x"}], "categories": [{"id": "c", "group": "A", "it": "x", "en": "x", "terms": [\#(term), \#(term)]}]}"#)
    #expect(PMData.load(folder: folder).warnings == [.repeatedIDs(file: "prompt-database.json")])
    try write(#"{"schema": 1, "version": "99.0.0", "groups": [{"id": "A", "it": "x", "en": "x"}], "categories": [{"id": "c", "group": "A", "it": "x", "en": "x", "terms": [\#(term)]}, {"id": "d", "group": "A", "it": "x", "en": "x", "terms": [\#(term)]}]}"#)
    #expect(PMData.load(folder: folder).warnings == [.repeatedIDs(file: "prompt-database.json")])
    try write(#"{"schema": 1, "version": "99.0.0", "groups": [{"id": "A", "it": "x", "en": "x"}], "categories": [{"id": "c", "group": "A", "it": "x", "en": "x", "terms": []}, {"id": "c", "group": "A", "it": "x", "en": "x", "terms": []}]}"#)
    #expect(PMData.load(folder: folder).warnings == [.repeatedIDs(file: "prompt-database.json")])
    try write(#"{"schema": 1, "version": "99.0.0", "groups": [{"id": "A", "it": "x", "en": "x"}, {"id": "A", "it": "y", "en": "y"}], "categories": []}"#)
    let data = PMData.load(folder: folder)
    #expect(data.database == PMData.embeddedDatabase && data.warnings == [.repeatedIDs(file: "prompt-database.json")])
    #expect(try String(contentsOf: file, encoding: .utf8).contains(#""id": "A", "it": "y""#))  // never touched
  }

  @Test func aFileWithUniqueIdsIsStillAccepted() throws {
    let folder = try makeFolder()
    try databaseJSON(version: "99.0.0").write(to: folder.appendingPathComponent("prompt-database.json"))
    #expect(PMData.load(folder: folder).warnings.isEmpty)
  }

  @Test func theFamiliesFileLivesInThePluginsOwnFolder() throws {
    let folder = try makeFolder()
    var families = PMData.embeddedFamilies
    families.version = "99.0.0"
    families.families["flux1"]?.hiddenCategories = ["render_quality"]
    try JSONEncoder().encode(families).write(to: folder.appendingPathComponent("prompt-master/families.json"))
    #expect(PMData.load(folder: folder).families.families["flux1"]?.hiddenCategories == ["render_quality"])
  }

  @Test func versionsAreComparedNumberByNumber() {
    #expect(DataSource.isOlder("2.9.0", than: "2.10.0"))
    #expect(!DataSource.isOlder("2.10.0", than: "2.9.0"))
    #expect(!DataSource.isOlder("2.1", than: "2.1.0"))
    #expect(DataSource.isOlder("2.1", than: "2.1.1"))
    #expect(!DataSource.isOlder("abc", than: "0"))
  }
}
