import Testing

@testable import CharacterSheet

@Suite("CSAnswer")
struct CSAnswerTests {
  @Test func plainProse() {
    #expect(CSAnswer.parse("  Ten sections.\n") == "Ten sections.")
  }

  @Test func blankLinesBetweenParagraphsStay() {
    #expect(CSAnswer.parse("1. A\n\n2. B") == "1. A\n\n2. B")
  }

  @Test func oneQuotePairIsRemoved() {
    #expect(CSAnswer.parse("\"A\"") == "A")
    #expect(CSAnswer.parse("“A”") == "A")
    #expect(CSAnswer.parse("\"A\" and \"B\"") == "\"A\" and \"B\"")
  }

  @Test func rewrittenPromptOfTheEnhancer() {
    let raw = "{\"rewritten_prompt\": \"Make a sheet.\", \"wh_ratio\": \"3:2\", \"ratio_follow\": \"\"}"
    #expect(CSAnswer.parse(raw) == "Make a sheet.")
  }

  @Test func promptAliases() {
    #expect(CSAnswer.parse("{\"prompt\":\"x\"}") == "x")
    #expect(CSAnswer.parse("{\"positive_prompt\":\"x\"}") == "x")
  }

  @Test func fencedJSON() {
    #expect(CSAnswer.parse("```json\n{\"rewritten_prompt\": \"x\"}\n```") == "x")
  }

  @Test func jsonSurroundedByChatter() {
    #expect(CSAnswer.parse("Here: {\"rewritten_prompt\": \"x\"} Done.") == "x")
  }

  @Test func thinkingBlockIsRemoved() {
    #expect(CSAnswer.parse("<think>hmm</think>Sheet") == "Sheet")
  }

  @Test func unclosedThinkingGivesNil() {
    #expect(CSAnswer.parse("<think>I should") == nil)
  }

  @Test func emptyGivesNil() {
    #expect(CSAnswer.parse("") == nil)
    #expect(CSAnswer.parse("   \n") == nil)
    #expect(CSAnswer.parse("```\n```") == nil)
  }

  @Test func jsonWithoutAPromptGivesNil() {
    #expect(CSAnswer.parse("{\"ratio_follow\": \"<image1>\"}") == nil)
    #expect(CSAnswer.parse("{\"wh_ratio\": \"3:2\", \"rewritten_prompt\": \"\"}") == nil)
  }

  @Test func malformedJSONIsTakenAsTheText() {
    #expect(CSAnswer.parse("{\"rewritten_prompt\": \"x\"") == "{\"rewritten_prompt\": \"x\"")
  }
}
