import Testing

@testable import PromptMasterF3

struct AnswerParserTests {
  let kinds: [F3Part.Kind] = [.description, .composition, .element(id: "woman_1")]

  @Test func parsesCleanAnswer() {
    let answer = "## description\nA rainy street.\n\n## composition\nA woman <woman_1> walks.\n\n## element: woman_1\nA young woman in a black coat."
    let parsed = F3AnswerParser.parse(answer, requested: kinds)
    #expect(parsed[.description] == "A rainy street.")
    #expect(parsed[.composition] == "A woman <woman_1> walks.")
    #expect(parsed[.element(id: "woman_1")] == "A young woman in a black coat.")
  }

  @Test func stripsThinkingAndFences() {
    let answer = "<think>hmm\n## description\nno</think>\n```\n## description\nReal text.\n```"
    #expect(F3AnswerParser.parse(answer, requested: [.description])[.description] == "Real text.")
  }

  @Test func unterminatedThinkIsDropped() {
    #expect(F3AnswerParser.parse("<think>never closed", requested: [.description]).isEmpty)
  }

  @Test func titlesInAnyOrderAndCase() {
    let answer = "## Element:woman_1\nShe stands.\n\n### COMPOSITION\nA <woman_1>."
    let parsed = F3AnswerParser.parse(answer, requested: kinds)
    #expect(parsed[.element(id: "woman_1")] == "She stands.")
    #expect(parsed[.composition] == "A <woman_1>.")
  }

  @Test func missingTitleIsAbsent() {
    let parsed = F3AnswerParser.parse("## description\nOnly this.", requested: kinds)
    #expect(parsed[.composition] == nil)
    #expect(parsed[.description] == "Only this.")
  }

  @Test func wrappingQuotesAreRemovedAndNewlinesBecomeSpaces() {
    let answer = "## description\n\"Line one\nline two.\""
    #expect(F3AnswerParser.parse(answer, requested: [.description, .composition])[.description] == "Line one line two.")
  }

  @Test func singleRequestWithoutTitlesTakesTheWholeText() {
    #expect(F3AnswerParser.parse("Just text.\n", requested: [.composition])[.composition] == "Just text.")
  }

  @Test func truncatedLastBlockIsDropped() {
    let answer = "## description\nDone.\n\n## composition\nA woman <wom"
    let parsed = F3AnswerParser.parse(answer, requested: kinds)
    #expect(parsed[.description] == "Done.")
    #expect(parsed[.composition] == nil)
  }

  @Test func unrequestedTitlesEndTheBlockAndAreIgnored() {
    let answer = "## description\nA.\n\n## element: ghost\nB."
    let parsed = F3AnswerParser.parse(answer, requested: [.description])
    #expect(parsed[.description] == "A.")
    #expect(parsed.count == 1)
  }
}
