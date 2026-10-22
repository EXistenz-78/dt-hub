import Testing

@testable import Flux3Editing

struct AnswerParserTests {
  let kinds: [EditPart.Kind] = [.prose, .element(id: "lamp_1"), .element(id: "chair_1")]

  @Test func parsesACleanAnswer() {
    let answer = "## prose\nModify <ref_image_0> by adding <lamp_1>.\n\n## element: lamp_1\nA brass lamp.\n\n## element: chair_1\nA red chair."
    let parsed = EditAnswerParser.parse(answer, requested: kinds)
    #expect(parsed[.prose] == "Modify <ref_image_0> by adding <lamp_1>.")
    #expect(parsed[.element(id: "lamp_1")] == "A brass lamp.")
    #expect(parsed[.element(id: "chair_1")] == "A red chair.")
  }

  @Test func stripsThinkingAndFences() {
    let answer = "<think>hmm\n## prose\nno</think>\n```\n## prose\nReal text.\n```"
    #expect(EditAnswerParser.parse(answer, requested: [.prose])[.prose] == "Real text.")
  }

  @Test func titlesInAnyOrderAndCase() {
    let parsed = EditAnswerParser.parse("## Element:lamp_1\nShe stands.\n\n### PROSE\nA <lamp_1>.", requested: kinds)
    #expect(parsed[.element(id: "lamp_1")] == "She stands." && parsed[.prose] == "A <lamp_1>.")
  }

  @Test func aTruncatedLastBlockIsDropped() {
    let parsed = EditAnswerParser.parse("## prose\nComplete.\n\n## element: lamp_1\nA brass la", requested: kinds)
    #expect(parsed[.prose] == "Complete." && parsed[.element(id: "lamp_1")] == nil)
  }

  @Test func oneRequestedPartMayComeWithoutATitle() {
    #expect(EditAnswerParser.parse("Just the text.", requested: [.prose])[.prose] == "Just the text.")
  }
}
