import Foundation
import Testing

@testable import PromptMasterMOSS

struct DocumentTests {
  @Test func defaultsAreSingleCanvasAndTheOfficialNegative() {
    let document = MossDocument()
    #expect(document.canvas == .single)
    #expect(document.negativeSelection == ["ng_worst_quality", "ng_bad_anatomy"])
    #expect(document.negativeText == "")
    #expect(document.nextItemID == 1)
    #expect(document.snapshot == nil)
    #expect(document.items.isEmpty)
  }

  @Test func theFiveLabelsAndThreeCanvasesAreTheOnesOfTheSpec() {
    #expect(MossLabel.allCases.map(\.rawValue) == ["object", "character", "text", "panel", "subject"])
    #expect(MossCanvas.allCases.map(\.rawValue) == ["single", "multi_panel", "collage"])
  }

  @Test func aDocumentSurvivesCodableWithEveryLabelAndASnapshot() throws {
    var document = MossDocument()
    document.description = "Una foresta"
    document.freeMeta = ["poster"]
    document.palette = ["#FFFFFF"]
    document.canvas = .collage
    for (index, label) in MossLabel.allCases.enumerated() {
      document.items.append(
        MossItem(
          id: index + 1, label: label, caption: "c\(index)", text: label == .text ? "Hi\nthere" : "", tags: "a, b",
          colors: ["#B22222"], box: FracBox(x0: 0.1, y0: 0.1, x1: 0.5, y1: 0.5), expanded: index == 0))
    }
    document.nextItemID = 6
    document.snapshot = MossSnapshot(
      description: "prima", selection: ["x"], freeMeta: ["m"], captions: [1: "uno", 2: "due"], tags: [1: "t"])
    let data = try JSONEncoder().encode(document)
    #expect(try JSONDecoder().decode(MossDocument.self, from: data) == document)
  }
}
