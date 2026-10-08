import Testing

@testable import CharacterSheet

@Suite("CSBuiltIn")
struct CSBuiltInTests {
  @Test func everyFileHasABuiltInText() {
    for file in CSTemplateFile.allCases {
      #expect(!CSBuiltIn.text(for: file).isEmpty, "\(file)")
      #expect(CSBuiltIn.text(for: file) == CSBuiltIn.text(for: file).trimmingCharacters(in: .whitespacesAndNewlines), "\(file)")
    }
  }

  @Test func theStaticPromptsCarryTheNamePlaceholderOnce() {
    for file in [CSTemplateFile.staticPrompt, .staticExpressions, .staticPoses] {
      #expect(CSBuiltIn.text(for: file).components(separatedBy: "{{name}}").count == 2, "\(file)")
    }
  }

  @Test func theMasterPromptsHaveNoPlaceholder() {
    for file in [CSTemplateFile.master, .masterExpressions, .masterPoses] {
      #expect(!CSBuiltIn.text(for: file).contains("{{name}}"), "\(file)")
    }
  }

  @Test func theSheetsSayWhereTheLabelsGo() {
    #expect(CSBuiltIn.text(for: .masterExpressions).contains("centered horizontally under its head"))
    #expect(CSBuiltIn.text(for: .masterPoses).contains("centered horizontally under its figure"))
    #expect(CSBuiltIn.text(for: .staticExpressions).contains("centered horizontally under the head"))
    #expect(CSBuiltIn.text(for: .staticPoses).contains("centered horizontally under the figure"))
  }

  @Test func theGridsAreTheOnesTheSheetsPromise() {
    #expect(CSBuiltIn.text(for: .masterExpressions).contains("four columns and three rows"))
    #expect(CSBuiltIn.text(for: .masterPoses).contains("five columns and two rows"))
  }
}
