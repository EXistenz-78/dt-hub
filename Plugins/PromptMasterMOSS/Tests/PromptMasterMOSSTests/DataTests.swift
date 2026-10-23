import Foundation
import Testing

@testable import PromptMasterMOSS

struct DataTests {
  @Test func embeddedFilesDecodeAndHaveUniqueIDs() {
    #expect(MossData.embeddedDatabase.hasUniqueIDs)
    #expect(MossData.embeddedDatabase.categories.count == 40)
    let config = MossData.embeddedConfig
    #expect(config.schema == 1)
    #expect(config.hiddenCategories == ["negative_terms"])
    #expect(config.extraNegativeTerms.map(\.id) == ["ng_worst_quality", "ng_low_quality"])
    #expect(config.options == MossConfig.LLMSettings(temperature: 0.6, maxTokens: 4096, thinking: false, timeout: 600))
  }

  func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("moss-data-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url.appendingPathComponent("prompt-master"), withIntermediateDirectories: true)
    return url
  }

  @Test func withoutFilesTheEmbeddedCopiesAreUsed() throws {
    let loaded = MossData.load(folder: try folder())
    #expect(loaded.warnings.isEmpty)
    #expect(loaded.config == MossData.embeddedConfig)
  }

  @Test func aReadableNewerConfigFileWins_anOlderOneDoesNot() throws {
    let dir = try folder()
    let url = dir.appendingPathComponent("prompt-master/moss.json")
    var config = MossData.embeddedConfig
    config.version = "9.0.0"
    config.metaCategories = ["photo_genre"]
    try JSONEncoder().encode(config).write(to: url)
    #expect(MossData.load(folder: dir).config.metaCategories == ["photo_genre"])
    config.version = "0.0.1"
    try JSONEncoder().encode(config).write(to: url)
    #expect(MossData.load(folder: dir).config == MossData.embeddedConfig)
  }

  @Test func anUnreadableConfigFileFallsBackWithAWarning() throws {
    let dir = try folder()
    try Data("not json".utf8).write(to: dir.appendingPathComponent("prompt-master/moss.json"))
    let loaded = MossData.load(folder: dir)
    #expect(loaded.config == MossData.embeddedConfig)
    #expect(loaded.warnings == [.unreadable(file: "moss.json")])
  }
}
