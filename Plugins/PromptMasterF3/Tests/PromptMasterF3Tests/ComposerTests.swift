import Foundation
import Testing

@testable import PromptMasterF3

struct ComposerTests {
  func element(_ id: String, _ desc: String = "d", box: BBox = BBox(y0: 1, x0: 2, y1: 300, x1: 400)) -> F3Element {
    F3Element(id: id, desc: desc, box: box, colorIndex: 0, expanded: false)
  }

  @Test func textJoinsThreePartsWithBlankLines() {
    let out = F3Composer.text(
      description: "A.", terms: [], composition: "B <x_1>.", elements: [element("x_1", "d", box: BBox(y0: 20, x0: 30, y1: 300, x1: 400))])
    let expected = "A.\n\nB <x_1>.\n\n[\n  {\n    \"id\": \"x_1\",\n    \"bbox\": [20, 30, 300, 400],\n    \"desc\": \"d\"\n  }\n]"
    #expect(out == expected)
  }

  @Test func textAppendsTermsAsSentence() {
    let out = F3Composer.text(description: "A scene.", terms: ["Neon light", "rim light"], composition: "C", elements: [])
    #expect(out.hasPrefix("A scene. Neon light, rim light.\n\nC"))
    let only = F3Composer.text(description: "", terms: ["Neon light"], composition: "C", elements: [])
    #expect(only.hasPrefix("Neon light.\n\nC"))
  }

  @Test func jsonEscapesQuotesBackslashNewlineEmoji() throws {
    let desc = "a \"b\" \\ c\nd 😀"
    let json = F3Composer.jsonArray([element("x", desc)])
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
    #expect(object?.first?["desc"] as? String == desc)
    #expect(object?.first?["bbox"] as? [Int] == [1, 2, 300, 400])
  }

  @Test func jsonOfNoElementsIsEmptyArray() {
    #expect(F3Composer.jsonArray([]) == "[]")
  }

  @Test func problemsFlagEmptyDescAndDuplicates() {
    let list = [element("a", ""), element("b"), element("b")]
    let problems = F3Composer.problems(composition: "<a> <b> <b>", elements: list)
    #expect(problems.contains(.emptyDescription(id: "a")))
    #expect(problems.contains(.duplicateID("b")))
    #expect(!problems.contains(.noElements))
  }

  @Test func problemsNoElements() {
    #expect(F3Composer.problems(composition: "", elements: []) == [.noElements])
  }

  @Test func whitespaceOnlyDescIsEmpty() {
    #expect(F3Composer.problems(composition: "<a>", elements: [element("a", "  \n")]) == [.emptyDescription(id: "a")])
  }
}
