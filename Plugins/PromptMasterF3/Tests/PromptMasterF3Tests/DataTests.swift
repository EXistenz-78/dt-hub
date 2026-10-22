import Foundation
import Testing

@testable import PromptMasterF3

struct DataTests {
  @Test func embeddedDataDecodesAndIsConsistent() {
    let data = F3Data.load(folder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    #expect(data.warnings.isEmpty)
    #expect(data.database.hasUniqueIDs)
    #expect(data.config.excludedGroups == ["H"])
    let ids = Set(data.database.categories.map(\.id))
    #expect(Set(data.config.photoOnly + data.config.artOnly).isSubset(of: ids))
    #expect(data.config.options.thinking == false && data.config.options.maxTokens == 4096)
  }

  @Test func masterPromptHasTheRules() {
    #expect(EmbeddedData.masterPrompt.contains("NEVER change"))
    #expect(EmbeddedData.masterPrompt.contains("## composition"))
  }
}
