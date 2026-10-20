import Testing

@testable import PromptMasterF3

struct IDParserTests {
  func ids(_ text: String) -> [String] { F3IDParser.ids(in: text).map(\.id) }

  @Test func findsSimpleIDs() {
    #expect(ids("a woman <woman_1> and <umbrella_1>.") == ["woman_1", "umbrella_1"])
  }

  @Test func trimsSpacesAtTheEdges() {
    #expect(ids("< a >") == ["a"])
  }

  @Test func ignoresEmptyTags() {
    #expect(ids("<> and < > and <   >") == [])
  }

  @Test func nestedTakesTheInnerOne() {
    #expect(ids("<a<b>>") == ["b"])
  }

  @Test func ignoresTooLongIDs() {
    let long = String(repeating: "x", count: 41)
    #expect(ids("<\(long)>") == [])
    #expect(ids("<\(String(repeating: "x", count: 40))>").count == 1)
  }

  @Test func ignoresNewlineInside() {
    #expect(ids("<a\nb>") == [])
  }

  @Test func keepsRepeatsInOrder() {
    #expect(ids("<w_1>, <w_1>, <x>") == ["w_1", "w_1", "x"])
  }

  @Test func unclosedTagIsNotAnID() {
    #expect(ids("a woman <woman_") == [])
  }

  @Test func rangeCoversTheWholeToken() {
    let text = "go <abc> now"
    let match = F3IDParser.ids(in: text)[0]
    #expect(String(text[match.range]) == "<abc>")
  }
}
