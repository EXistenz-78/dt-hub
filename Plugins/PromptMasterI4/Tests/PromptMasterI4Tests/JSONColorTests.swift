import AppKit
import Foundation
import Testing

@testable import PromptMasterI4

@Suite("The colors of the JSON")
struct JSONColorTests {
  private func texts(_ json: String) -> [String] {
    let text = json as NSString
    return JSONHighlight.descriptiveRanges(in: json).map { text.substring(with: $0) }
  }

  private let caption = I4Caption(
    description: "A neon-lit diner at night.", aesthetics: "A calm mood.", lighting: "Lit by neon.", style: "A medium shot.",
    medium: "On film.", mode: .photo, colors: ["#0B1F3A", "#FF2E63"], background: "A wet street.",
    elements: [
      .init(type: .obj, bbox: BBox(y0: 320, x0: 120, y1: 900, x1: 560), text: "ignored", desc: "A lone customer.", colors: ["#F5E6CC"]),
      .init(type: .text, bbox: nil, text: "OPEN ALL NIGHT", desc: "Neon lettering.", colors: []),
    ])

  @Test func everyDescriptiveTextIsColoredAndNothingThatIsStructure() {
    #expect(
      texts(caption.json) == [
        "A neon-lit diner at night.", "A calm mood.", "Lit by neon.", "A medium shot.", "On film.", "A wet street.",
        "A lone customer.", "OPEN ALL NIGHT", "Neon lettering.",
      ])
  }

  @Test func theArtStyleIsDescriptiveToo() {
    var art = caption
    art.mode = .art
    #expect(texts(art.json).contains("A medium shot."))
  }

  @Test func keysTypesColorCodesAndCoordinatesAreNeverColored() {
    let all = texts(caption.json).joined(separator: "|")
    for structural in ["high_level_description", "style_description", "obj", "#0B1F3A", "#F5E6CC", "320", "bbox", "color_palette", "type"] {
      #expect(!all.contains(structural), "\(structural)")
    }
  }

  @Test func theRangesAreInUTF16UnitsAndEscapesStayInsideTheText() {
    let json = "{\n  \"desc\": \"Caffè \\\"Roma\\\" ☕ \\\\ end\",\n  \"x\": \"not colored\"\n}"
    let ranges = JSONHighlight.descriptiveRanges(in: json)
    #expect(ranges.count == 1)
    #expect((json as NSString).substring(with: ranges[0]) == "Caffè \\\"Roma\\\" ☕ \\\\ end")
  }

  @Test func textThatIsNotValidJSONStillColorsWhatItCanAndNeverCrashes() {
    #expect(texts("{ \"desc\": \"a\", \"background\": \"b") == ["a"])  // the last string never closes
    #expect(texts("not json at all") == [])
    #expect(texts("") == [])
    #expect(texts("\"desc\": \"loose\"") == ["loose"])
    #expect(texts("{ \"desc\": }") == [] && texts("{ \"desc\" \"x\" }") == [])
    #expect(texts("\"") == [] && texts("\\") == [])
  }

  @Test func aValueUnderAKeyOfAnotherNameIsNotColored() {
    #expect(texts("{ \"type\": \"obj\", \"color_palette\": [\"#FFFFFF\"], \"desc\": \"yes\" }") == ["yes"])
    // An array item of a descriptive key is not a value of it.
    #expect(texts("{ \"desc\": [\"a\", \"b\"] }") == [])
  }

  @MainActor @Test func theEditorPaintsTheRangesAndRepaintsAfterAnEdit() {
    let view = NSTextView()
    JSONEditor.configure(view)
    view.string = "{ \"desc\": \"hello\", \"type\": \"obj\" }"
    JSONEditor.highlight(view)
    let storage = view.textStorage!
    let text = view.string as NSString
    let hello = text.range(of: "hello"), key = text.range(of: "desc"), type = text.range(of: "obj")
    let teal = storage.attribute(.foregroundColor, at: hello.location, effectiveRange: nil) as? NSColor
    let plain = storage.attribute(.foregroundColor, at: key.location, effectiveRange: nil) as? NSColor
    #expect(teal != nil && plain != nil && teal != plain)
    #expect(storage.attribute(.foregroundColor, at: type.location, effectiveRange: nil) as? NSColor == plain)
    view.string = "{ \"type\": \"obj\", \"desc\": \"moved\" }"
    JSONHighlight_repaint(view)
    let moved = (view.string as NSString).range(of: "moved")
    #expect(storage.attribute(.foregroundColor, at: moved.location, effectiveRange: nil) as? NSColor == teal)
    #expect(storage.attribute(.foregroundColor, at: (view.string as NSString).range(of: "type").location, effectiveRange: nil) as? NSColor == plain)
  }

  /// The editor repaints from the whole text every time.
  @MainActor private func JSONHighlight_repaint(_ view: NSTextView) { JSONEditor.highlight(view) }
}
