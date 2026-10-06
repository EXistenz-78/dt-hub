import Foundation
import Testing

@testable import PromptMasterI4

@Suite("The answer of the language model")
struct AnswerParserTests {
  private let tags = ["high_level_description", "aesthetics", "element_1"]

  @Test func eachRequestedTagGivesItsSentenceAndTheRestIsIgnored() {
    let answer = """
      Sure! Here you go:
      <high_level_description>Two friends in a diner.</high_level_description>
      <aesthetics>
      A calm,
      peaceful mood.
      </aesthetics>
      <element_1 kind="object">A lone cup.</element_1>
      <lighting>Not asked.</lighting>
      """
    #expect(
      I4AnswerParser.parse(answer, tags: tags) == [
        "high_level_description": "Two friends in a diner.", "aesthetics": "A calm, peaceful mood.", "element_1": "A lone cup.",
      ])
  }

  @Test func tagNamesIgnoreCaseSpacesAndDashes() {
    let found = I4AnswerParser.parse("<High level description>A.</High level description>\n<AESTHETICS>B.</aesthetics>\n<Element-1>C.</element-1>", tags: tags)
    #expect(found == ["high_level_description": "A.", "aesthetics": "B.", "element_1": "C."])
  }

  @Test func reasoningAndCodeFencesGoAndQuotesAroundASentenceToo() {
    #expect(I4AnswerParser.parse("<think>hmm <aesthetics>no</aesthetics></think><aesthetics>\"Calm.\"</aesthetics>", tags: tags) == ["aesthetics": "Calm."])
    #expect(I4AnswerParser.parse("```xml\n<aesthetics>Calm.</aesthetics>\n```", tags: tags) == ["aesthetics": "Calm."])
    #expect(I4AnswerParser.parse("<think>never closed <aesthetics>Calm.</aesthetics>", tags: tags).isEmpty)
  }

  @Test func aTagThatIsEmptyOrMissingIsMissingAndTheLastNonEmptyOneWins() {
    #expect(I4AnswerParser.parse("<aesthetics>  </aesthetics>", tags: tags).isEmpty)
    #expect(I4AnswerParser.parse("<aesthetics>First.</aesthetics><aesthetics>Second.</aesthetics><aesthetics></aesthetics>", tags: tags) == ["aesthetics": "Second."])
    #expect(I4AnswerParser.parse("<aesthetics>No end", tags: tags).isEmpty)
    #expect(I4AnswerParser.parse("<aesthetics>A</medium>", tags: tags).isEmpty)  // the tags do not match
  }

  @Test func withOneTagAskedAnAnswerWithoutTagsIsTheSentenceAndWithMoreItIsNothing() {
    #expect(I4AnswerParser.parse("  A calm mood.\n", tags: ["aesthetics"]) == ["aesthetics": "A calm mood."])
    #expect(I4AnswerParser.parse("A calm mood.", tags: ["aesthetics", "lighting"]).isEmpty)
    // But an answer that has other tags is not a bare sentence.
    #expect(I4AnswerParser.parse("<lighting>Lit.</lighting>", tags: ["aesthetics"]).isEmpty)
    #expect(I4AnswerParser.parse("", tags: ["aesthetics"]).isEmpty)
    #expect(I4AnswerParser.parse("<aesthetics>oops</wrong>", tags: ["aesthetics"]).isEmpty)  // a broken tag is no sentence
  }

  @Test func theDotsOfTheShapeAreNeverASentenceNotEvenWhenTheModelEchoesTheShapeAfterItsAnswer() {
    #expect(I4AnswerParser.parse("<aesthetics>Calm.</aesthetics><lighting>...</lighting>", tags: tags) == ["aesthetics": "Calm."])
    let echoed = "<aesthetics>Calm.</aesthetics>\nReply in exactly this shape:\n<aesthetics>...</aesthetics>"
    #expect(I4AnswerParser.parse(echoed, tags: tags) == ["aesthetics": "Calm."])
    #expect(I4AnswerParser.parse("<aesthetics> … </aesthetics>", tags: tags).isEmpty)
    #expect(I4AnswerParser.parse("...", tags: ["aesthetics"]).isEmpty)
    #expect(I4AnswerParser.parse("<aesthetics>Wait... what?</aesthetics>", tags: tags) == ["aesthetics": "Wait... what?"])
  }

  @Test func aDegenerateAnswerIsReadInAFractionOfASecond() {
    // A model that loops on white space after an opening bracket: the first reading of this took seconds, then minutes.
    let clock = ContinuousClock()
    let answers = [
      "<tagname" + String(repeating: " ", count: 16_000), String(repeating: "< ", count: 8_000),
      "<aesthetics>" + String(repeating: "<b ", count: 6_000), String(repeating: "<aesthetics>", count: 12_000),
    ]
    for answer in answers {
      let elapsed = clock.measure { _ = I4AnswerParser.parse(answer, tags: tags) }
      #expect(elapsed < .seconds(1), "\(answer.prefix(20)): \(elapsed)")
    }
  }

  @Test func anUnclosedTagDoesNotLoseTheNextOne() {
    #expect(I4AnswerParser.parse("<aesthetics>Calm.\n<lighting>Soft.</lighting>", tags: tags + ["lighting"]) == ["lighting": "Soft."])
    #expect(I4AnswerParser.parse("<element_1>A cup.</element_1><element_1>", tags: tags) == ["element_1": "A cup."])
  }
}
