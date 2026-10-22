import Testing

@testable import PromptMasterI4

@MainActor
struct IconTests {
  /// A plug-in that does the same as another for a different model never shows with it: it takes the same toolbar icon
  /// (here the one of Prompt Master).
  @Test func theIconIsTheOneOfPromptMaster() {
    #expect(PromptMasterI4Plugin().manifest.symbol == "wand.and.stars")
  }
}
