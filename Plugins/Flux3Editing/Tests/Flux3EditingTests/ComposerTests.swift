import CoreGraphics
import Foundation
import Testing

@testable import Flux3Editing

struct ComposerTests {
  private func box(_ y0: Int, _ x0: Int, _ y1: Int, _ x1: Int) -> BBox { BBox(y0: y0, x0: x0, y1: y1, x1: x1) }
  private let refs = RefNumbering.references(
    moodboard: ["/s/a.png", "/s/b.png"], sizes: { _ in CGSize(width: 300, height: 200) })

  private func element(_ id: String, _ kind: EditKind, ref: String? = nil, src: BBox? = nil, tgt: BBox? = nil, desc: String = "d")
    -> EditElement
  { EditElement(id: id, colorIndex: 0, kind: kind, refFile: ref, src: src, tgt: tgt, desc: desc) }

  private func doc(_ prose: String, _ elements: [EditElement]) -> EditDocument {
    var d = EditDocument()
    d.prose = prose
    d.elements = elements
    return d
  }

  private func doc(_ elements: [EditElement]) -> EditDocument { doc("Modify <ref_image_0>.", elements) }

  @Test func theTextIsTheProseThenTheJSONArrayInTheFixedOrder() {
    let d = doc([element("lamp_1", .fromReference, ref: "b.png", src: box(250, 180, 820, 620), tgt: box(300, 550, 550, 720), desc: "A lamp.")])
    let expected = """
      Modify <ref_image_0>.

      [
        {
          "id": "lamp_1",
          "from": "ref_image_2",
          "src_bbox": [250, 180, 820, 620],
          "tgt_bbox": [300, 550, 550, 720],
          "desc": "A lamp."
        }
      ]
      """
    #expect(EditComposer.text(d, refs: refs) == expected)
  }

  @Test func newWritesNullFromAndNullSource() {
    let text = EditComposer.text(doc([element("vase_1", .new, tgt: box(570, 430, 700, 560))]), refs: refs)
    #expect(text.contains("\"from\": null,\n    \"src_bbox\": null,\n    \"tgt_bbox\": [570, 430, 700, 560]"))
  }

  @Test func existingWritesTheSameBoxTwice() {
    let text = EditComposer.text(doc([element("bg_1", .existing, src: box(0, 0, 1000, 1000))]), refs: refs)
    #expect(text.contains("\"from\": \"ref_image_0\",\n    \"src_bbox\": [0, 0, 1000, 1000],\n    \"tgt_bbox\": [0, 0, 1000, 1000]"))
  }

  @Test func moveWritesTwoDifferentBoxes() {
    let text = EditComposer.text(doc([element("lamp_1", .move, src: box(250, 100, 850, 300), tgt: box(300, 760, 900, 960))]), refs: refs)
    #expect(text.contains("\"src_bbox\": [250, 100, 850, 300],\n    \"tgt_bbox\": [300, 760, 900, 960]"))
  }

  @Test func removeWritesANullTarget() {
    let text = EditComposer.text(doc([element("sign_1", .remove, src: box(10, 20, 300, 400))]), refs: refs)
    #expect(text.contains("\"from\": \"ref_image_0\",\n    \"src_bbox\": [10, 20, 300, 400],\n    \"tgt_bbox\": null"))
  }

  @Test func elementsFollowTheOrderOfTheCards() {
    let d = doc([element("b", .new, tgt: box(0, 0, 100, 100)), element("a", .new, tgt: box(0, 0, 100, 100))])
    let text = EditComposer.text(d, refs: refs)
    #expect(text.range(of: "\"b\"")!.lowerBound < text.range(of: "\"a\"")!.lowerBound)
  }

  @Test func descriptionsAndIDsWithQuotesNewlinesAndAnglesStayValidJSON() throws {
    let d = doc([element("we\"ird<id>", .new, tgt: box(0, 0, 100, 100), desc: "She said \"hi\"\nthen left \\ <x>")])
    let text = EditComposer.text(d, refs: refs)
    let array = String(text[text.range(of: "[\n")!.lowerBound...])
    let parsed = try #require(JSONSerialization.jsonObject(with: Data(array.utf8)) as? [[String: Any]])
    #expect(parsed[0]["id"] as? String == "we\"ird<id>")
    #expect(parsed[0]["desc"] as? String == "She said \"hi\"\nthen left \\ <x>")
    #expect(parsed[0]["from"] is NSNull && parsed[0]["src_bbox"] is NSNull)
  }

  @Test func anEmptyProseLeavesOnlyTheArray() {
    let text = EditComposer.text(doc("  ", [element("a", .new, tgt: box(0, 0, 100, 100))]), refs: refs)
    #expect(text.hasPrefix("[\n  {"))
  }

  @Test func aPairWhoseImageLeftTheMoodboardIsNotWritten() {
    let d = doc([
      element("gone_1", .fromReference, ref: "zzz.png", src: box(0, 0, 100, 100), tgt: box(0, 0, 100, 100)),
      element("a", .new, tgt: box(0, 0, 100, 100)),
    ])
    let text = EditComposer.text(d, refs: refs)
    #expect(!text.contains("gone_1") && text.contains("\"a\""))
  }

  @Test func withoutElementsTheArrayIsEmpty() {
    #expect(EditComposer.text(doc("Hi", []), refs: refs) == "Hi\n\n[]")
  }

  // MARK: Invia e avvisi

  @Test func theProblemsThatBlockSending() {
    #expect(EditComposer.problems(doc([]), refs: refs, hasStartImage: false) == [.noStartImage, .noElements])
    let d = doc([
      element("a", .new, tgt: box(0, 0, 100, 100), desc: " "),
      element("a", .existing, src: box(0, 0, 100, 100), desc: ""),
      element("r", .remove, src: box(0, 0, 100, 100), desc: ""),
      element("m", .move, src: box(0, 0, 100, 100), tgt: box(0, 200, 100, 300), desc: ""),
      element("g", .fromReference, ref: "zzz.png", src: box(0, 0, 100, 100), tgt: box(0, 0, 100, 100), desc: "x"),
      element("", .new, tgt: box(0, 0, 100, 100), desc: "x"),
    ])
    let problems = EditComposer.problems(d, refs: refs, hasStartImage: true)
    #expect(problems.contains(.emptyDescription("a")))
    #expect(problems.contains(.repeatedID("a")))
    #expect(problems.contains(.imageMissing("g")))
    #expect(problems.contains(.emptyID))
    #expect(!problems.contains(.emptyDescription("r")) && !problems.contains(.emptyDescription("m")))
    #expect(!problems.contains(.noStartImage) && !problems.contains(.noElements))
  }

  @Test func aCleanDocumentHasNoProblems() {
    let d = doc([element("a", .new, tgt: box(0, 0, 100, 100))])
    #expect(EditComposer.problems(d, refs: refs, hasStartImage: true).isEmpty)
  }

  @Test func theWarningsDoNotBlock() {
    let d = doc("Add <a> next to <ref_image_5>.", [element("a", .new, tgt: box(0, 0, 100, 100)), element("b", .new, tgt: box(0, 0, 100, 100))])
    let warnings = EditComposer.warnings(d, refs: refs)
    #expect(warnings.contains(.idNotInProse("b")) && !warnings.contains(.idNotInProse("a")))
    #expect(warnings.contains(.unknownReferenceInProse(5)))
    #expect(!warnings.contains(.unknownReferenceInProse(0)))
    let many = RefNumbering.references(moodboard: (0..<10).map { "/s/\($0).png" }, sizes: { _ in nil })
    #expect(EditComposer.warnings(doc("<a>", [element("a", .new, tgt: box(0, 0, 100, 100))]), refs: many).contains(.tooManyImages))
  }
}
