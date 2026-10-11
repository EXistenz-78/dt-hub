import Testing

@testable import HubCore

struct EmbeddedPromptsTests {
  @Test func thirteenFamiliesAllParseAsValid() {
    #expect(EmbeddedPrompts.families.count == 13)
    for (id, text) in EmbeddedPrompts.families {
      let file = PromptFile.parse(text)
      #expect(file.isValid, "\(id)")
      #expect(["label", "negative", "words", "maxWords", "version"].allSatisfy { file.header[$0] != nil }, "\(id)")
    }
  }

  @Test func eachFamilyAssemblesToTheSystemPromptOfToday() {
    let rules = PromptFile.parse(EmbeddedPrompts.rules["enhance"] ?? "")
    for (id, text) in EmbeddedPrompts.families {
      let family = PromptFile.parse(text)
      let values = [
        "label": family.header["label"] ?? "", "words": family.header["words"] ?? "",
        "maxWords": family.header["maxWords"] ?? "",
      ]
      let system = rules.resolved(values) + "\n\n" + family.resolved(values)
      #expect(system == LegacySystemPrompts.byFamily[id], "\(id)")
    }
    #expect(Set(LegacySystemPrompts.byFamily.keys) == Set(EmbeddedPrompts.families.keys))
  }

  @Test func theGenericOneEqualsToday() {
    let body = PromptFile.parse(EmbeddedPrompts.genericFamily).body
    #expect(EmbeddedPrompts.genericIntro + "\n\n" + body == LegacySystemPrompts.generic)
  }

  @Test func enhanceAndDescribeRulesAreValid() {
    for name in ["enhance", "describe"] {
      #expect(PromptFile.parse(EmbeddedPrompts.rules[name] ?? "").isValid, Comment(rawValue: name))
    }
  }
}
