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

  /// The most a family's prompt may have, in words (or tags for SD 1.5): the real limit of its text encoder with a margin
  /// (about 0.75 words per token), or the most the sources say works. Beyond it the prompt is cut off (FLUX, Z-Image),
  /// corrupts the picture (Krea 2) or is ignored (CLIP).
  private let ceilings: [String: ClosedRange<Int>] = [
    "flux1": 250...330, "flux2": 250...330, "flux2_9b": 250...330, "flux2_4b": 250...330,  // 512 tokens
    "krea_2": 250...330,  // 512 tokens; beyond that the picture is corrupted
    "qwen_image": 400...500, "qwen_image_2.1": 400...500,  // 1024 tokens by default
    "z_image": 250...330,  // 512 tokens, up to 1024 when asked
    "ernie_image": 250...330,  // 2048 characters
    "hidream_i1": 90...150,  // 128 tokens work, 248 at most
    "cosmos2.5_2b": 250...330,  // 512 tokens
    "sdxl_base_v0.9": 40...60, "v1": 30...45,  // 77 CLIP tokens
  ]

  @Test func everyFamilyHasACeilingThatFollowsTheRealLimitOfItsTextEncoderAndSaysIt() {
    for (family, prompt) in PMData.embeddedMasters.families {
      let ceiling = prompt.maxWords
      #expect(ceiling != nil && (ceilings[family] ?? 0...0).contains(ceiling ?? -1), "\(family): \(String(describing: ceiling))")
      guard let ceiling else { continue }
      #expect(prompt.system.contains("never beyond \(ceiling) "), "\(family) must tell the model its ceiling")
      #expect(prompt.lengthNote?.isEmpty == false, "\(family) must say why")
      // The usual range always fits under the ceiling.
      let top = prompt.words.split(separator: "-").last.flatMap { Int($0) } ?? Int.max
      #expect(top <= ceiling, "\(family): \(prompt.words) vs \(ceiling)")
    }
    #expect(Set(ceilings.keys) == Set(PMFamilies.all))
  }

  @Test func theLimitsThatWereNotInTheSourcesAreGone() {
    // Z-Image has no 800-character limit and does not lose attention after 75 tokens: it likes long, detailed prompts.
    let z = PMData.embeddedMasters.families["z_image"]
    #expect(z?.system.contains("800 characters") == false && z?.system.contains("75 tokens") == false)
    #expect((z?.words.split(separator: "-").last.flatMap { Int($0) } ?? 0) >= 200)
    // HiDream reads 128 tokens well and 248 at most: its usual range is shorter than FLUX's.
    #expect((PMData.embeddedMasters.families["hidream_i1"]?.maxWords ?? 999) < (PMData.embeddedMasters.families["flux1"]?.maxWords ?? 0))
  }

  /// The families that read natural language are told to enrich the scene, as long as nothing contradicts it.
  private let enriching: Set<String> = [
    "flux1", "flux2", "flux2_9b", "flux2_4b", "krea_2", "qwen_image", "qwen_image_2.1", "z_image", "ernie_image",
    "hidream_i1",
  ]

  @Test func theFamiliesThatReadNaturalLanguageAreAskedToEnrichWithoutContradicting() {
    for (family, prompt) in PMData.embeddedMasters.families {
      let asked = prompt.system.contains("Enrich the description")
      #expect(asked == enriching.contains(family), "\(family)")
      if asked {
        #expect(prompt.system.contains("never contradicts"), "\(family): the additions must not contradict the scene")
        #expect(!prompt.system.contains("Do not add subjects"), "\(family): the old ban on additions is replaced")
      } else {
        // Tag-based families keep the old, stricter rule.
        #expect(prompt.system.contains("Do not add subjects"), "\(family)")
      }
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
