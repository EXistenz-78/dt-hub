import Foundation
import Testing

@testable import Flux3Editing

struct HighlightTests {
  @Test func anElementTagTakesTheColorOfItsElement() {
    let text = "Add <el_2> and <lamp_1> next to <ref_image_1>."
    let spans = TagHighlight.spans(in: text, colors: ["el_2": 3, "lamp_1": 0])
    #expect(spans.count == 3)
    #expect((text as NSString).substring(with: spans[0].range) == "<el_2>" && spans[0].colorIndex == 3)
    #expect((text as NSString).substring(with: spans[1].range) == "<lamp_1>" && spans[1].colorIndex == 0)
  }

  @Test func aPictureTagIsNeutralAndAnUnknownTagIsLeftAlone() {
    let text = "<ref_image_0> and <ghost_9>"
    let spans = TagHighlight.spans(in: text, colors: ["el_1": 0])
    #expect(spans.count == 1 && spans[0].colorIndex == nil && (text as NSString).substring(with: spans[0].range) == "<ref_image_0>")
  }

  @Test func rangesAreInUTF16SoAccentsAndEmojiDoNotShiftThem() {
    let text = "Più 🙂 <el_1>"
    let spans = TagHighlight.spans(in: text, colors: ["el_1": 1])
    #expect((text as NSString).substring(with: spans[0].range) == "<el_1>")
  }

  @Test func noTagsNoSpans() {
    #expect(TagHighlight.spans(in: "plain text", colors: ["el_1": 0]).isEmpty)
    #expect(TagHighlight.spans(in: "", colors: [:]).isEmpty)
  }
}
