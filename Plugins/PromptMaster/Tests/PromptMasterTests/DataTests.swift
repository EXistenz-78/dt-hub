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

  @Test func theEmbeddedMasterPromptsCoverTheThirteenFamiliesAndAskForEnglish() {
    let masters = PMData.embeddedMasters
    #expect(Set(masters.families.keys) == Set(PMFamilies.all))
    #expect(PMFamilies.all.count == 13)
    for (family, prompt) in masters.families {
      #expect(prompt.system.contains("exclusively in English"), "\(family) must ask for English only")
      #expect(prompt.system.contains(prompt.label))
      // The JSON shape of the answer is the only place with braces: no placeholder was left unfilled.
      if !prompt.negative { #expect(!prompt.system.contains("{"), "\(family): an unfilled placeholder") }
      #expect(!prompt.system.contains("{label}") && !prompt.system.contains("{words}") && !prompt.system.contains("{notes}"))
    }
    // A family with a negative prompt asks for the JSON answer; one without does not.
    #expect(masters.families["sdxl_base_v0.9"]?.system.contains(#""negative""#) == true)
    #expect(masters.families["flux1"]?.system.contains(#""negative""#) == false)
    #expect(masters.families["flux1"]?.negative == false)
    #expect(masters.families["v1"]?.negative == true)
  }

  @Test func hiddenCategoriesAreRealOnesAndNegativeTermsAreHiddenWhereThereIsNoNegative() {
    let ids = Set(PMData.embeddedDatabase.categories.map(\.id))
    for (family, prompt) in PMData.embeddedMasters.families {
      #expect(Set(prompt.hiddenCategories).isSubset(of: ids), "\(family)")
      if !prompt.negative { #expect(prompt.hiddenCategories.contains("negative_terms"), "\(family)") }
    }
    #expect(PMData.embeddedMasters.families["z_image"]?.hiddenCategories.contains("typography_text") == true)
  }

  @Test func onlyTheTwoFamiliesWithTheBooruSwitchHaveItsText() {
    for (family, prompt) in PMData.embeddedMasters.families {
      #expect((prompt.booruSystem != nil) == PMFamilies.withBooruSwitch.contains(family), "\(family)")
    }
  }

  @Test func theFourFamiliesWithoutAReviewAreMarkedProvisional() {
    let provisional = PMData.embeddedMasters.families.filter { $0.value.provisional == true }.keys
    #expect(Set(provisional) == ["flux2", "qwen_image_2.1", "hidream_i1", "cosmos2.5_2b"])
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
    #expect(data.database == PMData.embeddedDatabase && data.masters == PMData.embeddedMasters && data.warnings.isEmpty)
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

  @Test func theMasterPromptsFileLivesInThePluginsOwnFolder() throws {
    let folder = try makeFolder()
    var masters = PMData.embeddedMasters
    masters.version = "99.0.0"
    masters.families["flux1"]?.system = "CHANGED exclusively in English"
    try JSONEncoder().encode(masters).write(to: folder.appendingPathComponent("prompt-master/master-prompts.json"))
    #expect(PMData.load(folder: folder).masters.families["flux1"]?.system == "CHANGED exclusively in English")
  }

  @Test func versionsAreComparedNumberByNumber() {
    #expect(DataSource.isOlder("2.9.0", than: "2.10.0"))
    #expect(!DataSource.isOlder("2.10.0", than: "2.9.0"))
    #expect(!DataSource.isOlder("2.1", than: "2.1.0"))
    #expect(DataSource.isOlder("2.1", than: "2.1.1"))
    #expect(!DataSource.isOlder("abc", than: "0"))
  }
}
