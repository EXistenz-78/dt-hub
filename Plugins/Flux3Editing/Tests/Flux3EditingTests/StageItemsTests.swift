import DTHubPluginKit
import Foundation
import Testing

@testable import Flux3Editing

@MainActor
struct StageItemsTests {
  private func box(_ y0: Int, _ x0: Int, _ y1: Int, _ x1: Int) -> BBox { BBox(y0: y0, x0: x0, y1: y1, x1: x1) }

  private func state() throws -> EditState {
    let s = EditState(store: EditStore(storage: MemoryStorage()), italian: false, imageSize: { _ in CGSize(width: 300, height: 200) })
    let json = #"{"type":"context","tempFolder":"/t","startImage":"/s/start.png","moodboard":["/s/a.png","/s/b.png"],"parameters":{"width":2048,"height":1664}}"#
    s.update(context: try JSONDecoder().decode(DTHubContext.self, from: Data(json.utf8)))
    return s
  }

  @Test func theReferenceStageShowsOnlyTheSourcesOfTheShownImage() throws {
    let s = try state()
    s.drawOnReference(box(100, 100, 400, 400))
    s.showReference(by: 1)
    s.drawOnReference(box(200, 200, 500, 500))
    let items = s.referenceItems
    #expect(items.count == 1 && items[0].elementID == "el_2" && items[0].role == .src && items[0].dashed)
    #expect(items[0].box == box(200, 200, 500, 500))
  }

  @Test func theCanvasShowsEachKindTheWayTheSpecDraws() throws {
    let s = try state()
    s.drawOnReference(box(100, 100, 400, 400))  // el_1 from reference: the target, solid
    s.drawOnCanvas(box(0, 0, 100, 100))  // el_2 new
    s.drawOnCanvas(box(0, 200, 100, 300))  // el_3 existing
    s.drawOnCanvas(box(0, 400, 100, 500))  // el_4 move
    s.drawOnCanvas(box(0, 600, 100, 700))  // el_5 remove
    s.document.setKind(.existing, of: "el_3")
    s.document.setKind(.move, of: "el_4")
    s.document.setKind(.remove, of: "el_5")
    let items = s.canvasItems
    func item(_ id: String, _ role: BoxRole) -> StageItem? { items.first { $0.elementID == id && $0.role == role } }
    #expect(item("el_1", .tgt)?.dashed == false && item("el_1", .src) == nil)
    #expect(item("el_2", .tgt)?.dashed == false)
    #expect(item("el_3", .src)?.dashed == false && item("el_3", .tgt) == nil)
    #expect(item("el_4", .src)?.dashed == true && item("el_4", .tgt)?.dashed == false)
    #expect(item("el_5", .src)?.dashed == true && item("el_5", .src)?.crossed == true && item("el_5", .tgt) == nil)
    #expect(item("el_4", .src)?.caption == "el_4 from" && item("el_4", .tgt)?.caption == "el_4 to")
    #expect(s.arrows.count == 1 && s.arrows[0].colorIndex == s.document.element("el_4")?.colorIndex)
  }

  @Test func aPairWhoseImageIsGoneIsNotDrawnOnTheCanvas() throws {
    let s = try state()
    s.showReference(by: 1)
    s.drawOnReference(box(100, 100, 400, 400))
    s.update(context: try JSONDecoder().decode(
      DTHubContext.self, from: Data(#"{"type":"context","tempFolder":"/t","startImage":"/s/start.png","moodboard":["/s/a.png"]}"#.utf8)))
    #expect(s.canvasItems.isEmpty && s.referenceItems.isEmpty)
  }

  @Test func movingABoxWritesTheRightField() throws {
    let s = try state()
    s.drawOnReference(box(100, 100, 400, 400))
    s.setBox(box(1, 2, 300, 400), itemID: "el_1|src")
    s.setBox(box(10, 20, 330, 440), itemID: "el_1|tgt")
    #expect(s.document.elements[0].src == box(1, 2, 300, 400) && s.document.elements[0].tgt == box(10, 20, 330, 440))
    s.drawOnCanvas(box(0, 0, 100, 100))
    s.document.setKind(.existing, of: "el_2")
    s.setBox(box(5, 5, 200, 200), itemID: "el_2|src")
    #expect(s.document.element("el_2")?.src == box(5, 5, 200, 200) && s.document.element("el_2")?.tgt == nil)
    s.setBox(box(5, 5, 200, 200), itemID: "nope|src")  // an unknown element changes nothing
    #expect(s.document.elements.count == 2)
  }

  @Test func selectingABoxSelectsItsElement() throws {
    let s = try state()
    s.drawOnCanvas(box(0, 0, 100, 100))
    s.drawOnCanvas(box(200, 200, 300, 300))
    s.selectItem("el_1|tgt")
    #expect(s.selected == "el_1")
    s.selectItem(nil)
    #expect(s.selected == nil)
  }
}
