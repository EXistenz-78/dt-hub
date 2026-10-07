import Testing

@testable import HubCore

struct PromptAnswerParserTests {
  @Test func plainProse() {
    #expect(
      PromptBrief.parse("  A cat on a roof at dusk.\n")
        == PromptPair(prompt: "A cat on a roof at dusk.", negative: ""))
  }

  @Test func oneQuotePairIsRemoved() {
    #expect(PromptBrief.parse("\"A cat\"")?.prompt == "A cat")
    #expect(PromptBrief.parse("“A cat”")?.prompt == "A cat")
    #expect(PromptBrief.parse("\"A\" and \"B\"")?.prompt == "\"A\" and \"B\"")
  }

  @Test func fencedJSON() {
    #expect(
      PromptBrief.parse("```json\n{\"prompt\": \"a, b\", \"negative\": \"blurry\"}\n```")
        == PromptPair(prompt: "a, b", negative: "blurry"))
  }

  @Test func jsonAliases() {
    #expect(
      PromptBrief.parse("{\"rewritten_prompt\":\"x\",\"negative_prompt\":\"y\"}")
        == PromptPair(prompt: "x", negative: "y"))
  }

  @Test func jsonSurroundedByChatter() {
    #expect(
      PromptBrief.parse("Here is the prompt: {\"prompt\": \"a cat\", \"negative\": \"dog\"} Hope it helps!")
        == PromptPair(prompt: "a cat", negative: "dog"))
  }

  @Test func malformedJSONIsTakenAsTheText() {
    #expect(PromptBrief.parse("{\"prompt\": \"a cat\"")?.prompt == "{\"prompt\": \"a cat\"")
  }

  @Test func thinkingBlockIsRemoved() {
    #expect(PromptBrief.parse("<think>hmm</think>A cat")?.prompt == "A cat")
  }

  @Test func unclosedThinkingGivesNil() {
    #expect(PromptBrief.parse("<think>I should describe a cat and") == nil)
  }

  @Test func emptyGivesNil() {
    #expect(PromptBrief.parse("") == nil)
    #expect(PromptBrief.parse("   \n") == nil)
    #expect(PromptBrief.parse("```\n```") == nil)
  }
}
