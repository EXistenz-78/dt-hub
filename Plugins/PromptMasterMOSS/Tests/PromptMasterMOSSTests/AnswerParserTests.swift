import Testing

@testable import PromptMasterMOSS

struct AnswerParserTests {
  let requested: [MossPart.Kind] = [.summary, .item(id: 1, label: .panel), .item(id: 2, label: .text), .tags(id: 2), .meta]

  @Test func aCleanAnswerIsSplitByTitle() {
    let answer = """
      ## summary
      Two friends in a bamboo forest.

      ## element 1 (panel)
      A dense backdrop of bamboo.

      ## element 2 (text)
      Small white lettering.

      ## tags 2
      lettering, white

      ## meta
      photograph, cinematic
      """
    let parsed = MossAnswerParser.parse(answer, requested: requested)
    #expect(parsed[.summary] == "Two friends in a bamboo forest.")
    #expect(parsed[.item(id: 1, label: .panel)] == "A dense backdrop of bamboo.")
    #expect(parsed[.item(id: 2, label: .text)] == "Small white lettering.")
    #expect(parsed[.tags(id: 2)] == "lettering, white")
    #expect(parsed[.meta] == "photograph, cinematic")
  }

  @Test func thinkingAndFencesAreRemoved() {
    let answer = "<think>hmm\n## summary\nwrong</think>\n```markdown\n## summary\nRight.\n```"
    #expect(MossAnswerParser.parse(answer, requested: [.summary])[.summary] == "Right.")
  }

  @Test func titlesInAnyOrderAndAnyCaseAreFound_theLabelInTheTitleDoesNotMatter() {
    let answer = "## ELEMENT 2 (object)\nSecond.\n##element 1\nFirst."
    let parsed = MossAnswerParser.parse(answer, requested: [.item(id: 1, label: .panel), .item(id: 2, label: .text)])
    #expect(parsed[.item(id: 1, label: .panel)] == "First.")
    #expect(parsed[.item(id: 2, label: .text)] == "Second.")
  }

  @Test func aMissingTitleIsAbsent() {
    let parsed = MossAnswerParser.parse("## summary\nOnly this.", requested: [.summary, .item(id: 1, label: .object)])
    #expect(parsed[.item(id: 1, label: .object)] == nil)
  }

  @Test func quotesAroundAWholeTextAreRemoved() {
    #expect(MossAnswerParser.parse("## summary\n\"A scene.\"", requested: [.summary])[.summary] == "A scene.")
  }

  @Test func aTruncatedLastProseBlockIsDropped_aTagListIsNot() {
    let truncated = "## summary\nA scene.\n\n## element 1 (panel)\nA dense backdrop of"
    let parsed = MossAnswerParser.parse(truncated, requested: [.summary, .item(id: 1, label: .panel)])
    #expect(parsed[.summary] == "A scene.")
    #expect(parsed[.item(id: 1, label: .panel)] == nil)
    let tags = MossAnswerParser.parse("## summary\nA scene.\n\n## meta\nphotograph, cinematic", requested: [.summary, .meta])
    #expect(tags[.meta] == "photograph, cinematic")
  }

  @Test func withASingleRequestedPartAndNoTitleTheWholeTextCounts() {
    #expect(MossAnswerParser.parse("Just the text.\nOn two lines.", requested: [.summary])[.summary] == "Just the text. On two lines.")
  }

  @Test func anUnrequestedTitleEndsTheBlockAndItsTextIsIgnored() {
    let parsed = MossAnswerParser.parse("## summary\nA scene.\n## element 9 (object)\nNot asked.", requested: [.summary])
    #expect(parsed == [.summary: "A scene."])
  }
}
