import Foundation
import Testing

@testable import PromptMasterI4

@Suite("The data files and the catalog")
struct DataTests {
  private let catalog = I4Catalog(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig)

  // MARK: The copies built into the plug-in

  @Test func theEmbeddedDatabaseIsTheOneOfPromptMaster() throws {
    // …/Plugins/PromptMasterI4/Tests/PromptMasterI4Tests/DataTests.swift → …/Plugins/PromptMaster/Data/prompt-database.json
    let shared = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PromptMaster/Data/prompt-database.json")
    let theirs = try JSONDecoder().decode(PromptDatabase.self, from: Data(contentsOf: shared))
    #expect(I4Data.embeddedDatabase == theirs)
    #expect(I4Data.embeddedDatabase.schema == DataSource.supportedSchema && I4Data.embeddedDatabase.hasUniqueIDs)
  }

  @Test func theEmbeddedConfigurationNamesRealCategoriesAndAsksForEnglishAndTheTags() {
    let config = I4Data.embeddedConfig
    #expect(config.schema == DataSource.supportedSchema)
    #expect(catalog.missingCategories.isEmpty)
    #expect(config.options == IdeogramConfig.LLMSettings(temperature: 0.6, maxTokens: 4096, thinking: false, timeout: 600))
    for tag in [
      "<high_level_description>", "<aesthetics>", "<lighting>", "<photo>", "<art_style>", "<medium>", "<background>",
      "<element_1>", "<already_written>", #"kind="text""#, "Printed text (never repeat it)", "English only",
    ] {
      #expect(config.system.contains(tag), "\(tag)")
    }
    // The rule about the overview and the details (spec §8, rule 7).
    #expect(config.system.contains("overview of the picture") && config.system.contains("never repeat its sentences"))
  }

  // MARK: The lists

  @Test func theMoodIsTheTwoMoodCategoriesMergedWithoutRepeatsIn31Terms() throws {
    let mood = try #require(catalog.categories(for: .aesthetics, mode: .photo).first)
    #expect(mood.id == "ij_mood_merged" && mood.en == "Mood" && mood.terms.count == 31)
    let names = mood.terms.map { $0.en.lowercased() }
    #expect(Set(names).count == 31)
    // The tone categories come first, then the mood ones.
    #expect(mood.terms.first?.id == "moodt_moody" && mood.terms.last?.id == "mo_whimsical")
    #expect(catalog.category(ofTerm: "moodt_moody")?.id == "ij_mood_merged")
  }

  @Test func eachFieldShowsTheCategoriesOfItsModeInTheOrderOfTheConfiguration() {
    func ids(_ field: I4Field, _ mode: StyleMode) -> [String] { catalog.categories(for: field, mode: mode).map(\.id) }
    #expect(ids(.aesthetics, .photo) == ["ij_mood_merged", "mood_aesthetic_register", "atmosphere", "color_harmony", "genre_aesthetic", "atmospheric_fx", "optical_fx"])
    #expect(ids(.aesthetics, .art) == ["ij_mood_merged", "mood_aesthetic_register", "atmosphere", "color_harmony", "genre_aesthetic", "atmospheric_fx"])
    #expect(ids(.lighting, .photo) == ["light_source", "light_quality", "light_scheme"] && ids(.lighting, .art) == ids(.lighting, .photo))
    #expect(ids(.style, .photo) == ["framing", "camera_angle", "composition", "lens_focus", "photo_genre"])
    #expect(ids(.style, .art).count == 7 && ids(.style, .art).first == "art_movement")
    #expect(ids(.medium, .photo) == ["medium_digital_3d", "film_stock_process"])
    #expect(ids(.medium, .art) == ["medium_digital_3d", "medium_paint_draw", "medium_print_craft"])
    #expect(ids(.background, .photo) == ["background_setup"] && catalog.categories(for: .background, mode: .photo)[0].terms.count == 12)
    #expect(catalog.lettering.count == 14 && catalog.lettering.first?.id == "ty_bold_sans")
  }

  @Test func theListsHaveTheTermCountsOfTheOldBuilder() {
    func count(_ field: I4Field, _ mode: StyleMode) -> Int { catalog.categories(for: field, mode: mode).flatMap(\.terms).count }
    // The badges of the old Prompt Master (spec §8.3): the Mood was already merged there (31 terms).
    #expect(count(.lighting, .photo) == 68 && count(.style, .photo) == 114 && count(.style, .art) == 146)
    #expect(count(.medium, .photo) == 40 && count(.medium, .art) == 64)
    #expect(count(.aesthetics, .photo) == 154 && count(.aesthetics, .art) == 126)
  }

  @Test func everyTermBelongsToOneFieldAndTheCategoriesAreNeverSharedBetweenFields() {
    var seen: [String: I4Field] = [:]
    for field in I4Field.allCases {
      for mode in [StyleMode.photo, .art] {
        for category in catalog.categories(for: field, mode: mode) {
          if let other = seen[category.id] { #expect(other == field, "\(category.id)") }
          seen[category.id] = field
          #expect(catalog.field(ofCategory: category.id) == field)
          for term in category.terms { #expect(catalog.term(term.id) == term) }
        }
      }
    }
  }

  @Test func aCategoryTheDatabaseLacksIsReportedAndLeftOutOfTheList() {
    var config = I4Data.embeddedConfig
    config.fields["lighting"]?.common = ["light_source", "no_such_category"]
    let broken = I4Catalog(database: I4Data.embeddedDatabase, config: config)
    #expect(broken.missingCategories == ["no_such_category"])
    #expect(broken.categories(for: .lighting, mode: .photo).map(\.id) == ["light_source"])
  }

  // MARK: Which copy wins

  private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("i4-data-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url.appendingPathComponent("prompt-master"), withIntermediateDirectories: true)
    return url
  }

  @Test func withoutFilesTheEmbeddedCopiesAreUsedSilently() throws {
    let data = I4Data.load(folder: try makeFolder())
    #expect(data.database == I4Data.embeddedDatabase && data.config == I4Data.embeddedConfig && data.warnings.isEmpty)
  }

  @Test func aNewerConfigurationFileInThePluginsFolderWins() throws {
    let folder = try makeFolder()
    var config = I4Data.embeddedConfig
    config.version = "99.0.0"
    config.system = "CHANGED"
    try JSONEncoder().encode(config).write(to: folder.appendingPathComponent("prompt-master/ideogram4.json"))
    #expect(I4Data.load(folder: folder).config.system == "CHANGED")
    config.version = "0.0.1"
    try JSONEncoder().encode(config).write(to: folder.appendingPathComponent("prompt-master/ideogram4.json"))
    #expect(I4Data.load(folder: folder).config == I4Data.embeddedConfig)  // older: the embedded one, no warning
  }

  @Test func aFileOfAnUnknownLayoutGarbageOrRepeatedIdsLosesWithAWarningAndIsLeftAlone() throws {
    let folder = try makeFolder()
    let file = folder.appendingPathComponent("prompt-database.json")
    try Data(#"{"schema": 2, "version": "99.0.0", "groups": [], "categories": []}"#.utf8).write(to: file)
    #expect(I4Data.load(folder: folder).warnings == [.unknownSchema(file: "prompt-database.json")])
    try Data("not json".utf8).write(to: file)
    #expect(I4Data.load(folder: folder).warnings == [.unreadable(file: "prompt-database.json")])
    #expect(try Data(contentsOf: file) == Data("not json".utf8))
    let term = #"{"id": "t1", "it": "a", "en": "a"}"#
    try Data(#"{"schema": 1, "version": "99.0.0", "groups": [], "categories": [{"id": "c", "group": "A", "it": "x", "en": "x", "terms": [\#(term), \#(term)]}]}"#.utf8).write(to: file)
    let data = I4Data.load(folder: folder)
    #expect(data.database == I4Data.embeddedDatabase && data.warnings == [.repeatedIDs(file: "prompt-database.json")])
  }

  @Test func versionsAreComparedNumberByNumber() {
    #expect(DataSource.isOlder("2.9.0", than: "2.10.0") && !DataSource.isOlder("2.10.0", than: "2.9.0"))
    #expect(!DataSource.isOlder("2.1", than: "2.1.0") && DataSource.isOlder("2.1", than: "2.1.1"))
  }
}
