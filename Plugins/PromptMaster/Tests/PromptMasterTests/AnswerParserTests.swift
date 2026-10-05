import Foundation
import Testing

@testable import PromptMaster

@Suite("Reading the answer")
struct AnswerParserTests {
  @Test func plainTextIsThePrompt() {
    #expect(AnswerParser.parse("  A quiet harbour at dawn.\n")?.prompt == "A quiet harbour at dawn.")
    #expect(AnswerParser.parse("A quiet harbour at dawn.")?.negative == nil)
  }

  @Test func aJSONAnswerGivesThePromptAndTheNegative() {
    let answer = AnswerParser.parse(#"{"prompt": "a cat on a sofa", "negative": "blurry, extra legs"}"#)
    #expect(answer == ParsedAnswer(prompt: "a cat on a sofa", negative: "blurry, extra legs", ratio: nil))
  }

  @Test func theEnhancersKeysAreReadToo() {
    let answer = AnswerParser.parse(#"{"rewritten_prompt": "a long prompt", "wh_ratio": "3:2"}"#)
    #expect(answer == ParsedAnswer(prompt: "a long prompt", negative: nil, ratio: "3:2"))
    #expect(AnswerParser.parse(#"{"positive_prompt": "edit it", "ratio_follow": 1}"#)?.prompt == "edit it")
  }

  @Test func thinkingBlocksAndFencesAreRemoved() {
    #expect(AnswerParser.parse("<think>hmm, a cat?</think>\nA cat.")?.prompt == "A cat.")
    #expect(AnswerParser.parse("<think>one</think> x <think>two</think>\nA cat.")?.prompt == "A cat.")
    #expect(AnswerParser.parse("```json\n{\"prompt\": \"a cat\", \"negative\": \"dog\"}\n```")?.negative == "dog")
    #expect(AnswerParser.parse("```\nA cat.\n```")?.prompt == "A cat.")
  }

  @Test func aThinkingBlockThatNeverClosesLeavesWhatCameBefore() {
    #expect(AnswerParser.parse("A cat.<think>and then it went on")?.prompt == "A cat.")
    #expect(AnswerParser.parse("<think>only thoughts") == nil)
  }

  @Test func textAroundTheJSONIsIgnored() {
    #expect(AnswerParser.parse("Here you go: {\"prompt\": \"a cat\"} Enjoy!")?.prompt == "a cat")
  }

  @Test func aMalformedJSONOrOneWithoutAPromptIsTakenAsText() {
    let broken = #"{"prompt": "a cat", "negative":"#
    #expect(AnswerParser.parse(broken)?.prompt == broken)
    let other = #"{"title": "a cat"}"#
    #expect(AnswerParser.parse(other)?.prompt == other)
  }

  @Test func oneWrappingPairOfQuotesGoes() {
    #expect(AnswerParser.parse("\"A cat.\"")?.prompt == "A cat.")
    #expect(AnswerParser.parse("“A cat.”")?.prompt == "A cat.")
    #expect(AnswerParser.parse("\"A cat\" and \"a dog\"")?.prompt == "\"A cat\" and \"a dog\"")  // quotes inside stay
  }

  @Test func nothingLeftIsNil() {
    #expect(AnswerParser.parse("") == nil)
    #expect(AnswerParser.parse("  \n ") == nil)
    #expect(AnswerParser.parse(#"{"prompt": "  "}"#)?.prompt == #"{"prompt": "  "}"#)
  }
}
