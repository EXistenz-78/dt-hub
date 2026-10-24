import Foundation
import Testing

@testable import Flux3Editing

struct DocumentTests {
  private func box(_ y0: Int, _ x0: Int, _ y1: Int, _ x1: Int) -> BBox { BBox(y0: y0, x0: x0, y1: y1, x1: x1) }

  @Test func drawingOnAReferenceCreatesThePairInTheMiddle() throws {
    var doc = EditDocument()
    doc.draw(onReference: "m1.png", box: box(250, 180, 820, 620))
    let element = try #require(doc.elements.first)
    #expect(element.kind == .fromReference && element.refFile == "m1.png")
    #expect(element.src == box(250, 180, 820, 620))
    let target = try #require(element.tgt)
    // No side above 30% of the grid, centered, same proportions as the source.
    #expect(max(target.y1 - target.y0, target.x1 - target.x0) == 300)
    #expect(abs((target.y0 + target.y1) / 2 - 500) <= 1 && abs((target.x0 + target.x1) / 2 - 500) <= 1)
    let sourceRatio = Double(440) / Double(570), targetRatio = Double(target.x1 - target.x0) / Double(target.y1 - target.y0)
    #expect(abs(sourceRatio - targetRatio) < 0.02)
  }

  @Test func aSmallSourceKeepsItsSizeAndTheMinimumSide() throws {
    var doc = EditDocument()
    doc.draw(onReference: "m1.png", box: box(100, 100, 150, 160))
    let target = try #require(doc.elements.first?.tgt)
    #expect(target.y1 - target.y0 >= BBox.minSide && target.x1 - target.x0 >= BBox.minSide)
    #expect(target.y1 - target.y0 == 50 && target.x1 - target.x0 == 60)
  }

  @Test func drawingOnTheCanvasCreatesANewElement() throws {
    var doc = EditDocument()
    doc.draw(onCanvas: box(10, 20, 300, 400))
    let element = try #require(doc.elements.first)
    #expect(element.kind == .new && element.src == nil && element.tgt == box(10, 20, 300, 400) && element.refFile == nil)
    #expect(element.id == "el_1" && element.desc == "")
  }

  @Test func idsTakeTheFirstFreeNumberAndColorsKeepRotating() {
    var doc = EditDocument()
    for _ in 0..<9 { doc.draw(onCanvas: box(0, 0, 100, 100)) }
    #expect(doc.elements.map(\.colorIndex) == Array(0..<9))
    #expect(doc.elements.map(\.id).last == "el_9")
    doc.delete("el_3")
    doc.draw(onCanvas: box(0, 0, 100, 100))
    #expect(doc.elements.last?.id == "el_3")
    // Deleting an element does not recolor the others.
    #expect(doc.elements.first { $0.id == "el_4" }?.colorIndex == 3)
    #expect(EditPalette.rgb.count == 8)
  }

  @Test func newToExistingKeepsTheBoxAsTheSource() throws {
    var doc = EditDocument()
    doc.draw(onCanvas: box(10, 20, 300, 400))
    doc.setKind(.existing, of: "el_1")
    let element = try #require(doc.elements.first)
    #expect(element.kind == .existing && element.src == box(10, 20, 300, 400) && element.tgt == nil)
  }

  @Test func existingToMoveCreatesTheTargetBesideIt() throws {
    var doc = EditDocument()
    doc.draw(onCanvas: box(100, 100, 300, 300))
    doc.setKind(.existing, of: "el_1")
    doc.setKind(.move, of: "el_1")
    let element = try #require(doc.elements.first)
    #expect(element.kind == .move && element.src == box(100, 100, 300, 300))
    #expect(element.tgt == box(100, 320, 300, 520))
  }

  @Test func theTargetBesideTheSourceStaysInsideTheGrid() throws {
    var doc = EditDocument()
    doc.draw(onCanvas: box(100, 700, 300, 1000))
    doc.setKind(.move, of: "el_1")
    let target = try #require(doc.elements.first?.tgt)
    #expect(target.x1 <= BBox.grid && target.x0 >= 0 && target.x1 - target.x0 == 300)
  }

  @Test func moveToRemoveKeepsOnlyTheSource() throws {
    var doc = EditDocument()
    doc.draw(onCanvas: box(100, 100, 300, 300))
    doc.setKind(.move, of: "el_1")
    doc.setKind(.remove, of: "el_1")
    let element = try #require(doc.elements.first)
    #expect(element.kind == .remove && element.src == box(100, 100, 300, 300) && element.tgt == nil)
  }

  @Test func moveToNewOrExistingKeepsTheTarget() throws {
    var doc = EditDocument()
    doc.draw(onCanvas: box(100, 100, 300, 300))
    doc.setKind(.move, of: "el_1")
    let target = try #require(doc.elements.first?.tgt)
    var asNew = doc
    asNew.setKind(.new, of: "el_1")
    #expect(asNew.elements[0].kind == .new && asNew.elements[0].tgt == target && asNew.elements[0].src == nil)
    var asExisting = doc
    asExisting.setKind(.existing, of: "el_1")
    #expect(asExisting.elements[0].src == target && asExisting.elements[0].tgt == nil)
  }

  @Test func removeToNewKeepsTheBox() throws {
    var doc = EditDocument()
    doc.draw(onCanvas: box(100, 100, 300, 300))
    doc.setKind(.remove, of: "el_1")
    doc.setKind(.new, of: "el_1")
    #expect(doc.elements[0].tgt == box(100, 100, 300, 300) && doc.elements[0].src == nil)
  }

  @Test func aTypeChangeKeepsIdColorAndDescription() throws {
    var doc = EditDocument()
    doc.draw(onCanvas: box(100, 100, 300, 300))
    doc.draw(onCanvas: box(400, 400, 600, 600))
    doc.elements[1].desc = "A red lamp"
    doc.elements[1].id = "lamp_1"
    doc.setKind(.remove, of: "lamp_1")
    #expect(doc.elements[1].id == "lamp_1" && doc.elements[1].colorIndex == 1 && doc.elements[1].desc == "A red lamp")
  }

  @Test func aPairFromAReferenceCannotChangeKind() throws {
    var doc = EditDocument()
    doc.draw(onReference: "m1.png", box: box(250, 180, 820, 620))
    let before = doc
    doc.setKind(.new, of: "el_1")
    #expect(doc == before)
  }

  @Test func elementsMoveUpAndDownAndStopAtTheEnds() {
    var doc = EditDocument()
    for _ in 0..<3 { doc.draw(onCanvas: box(0, 0, 100, 100)) }
    doc.moveElement("el_3", by: -1)
    #expect(doc.elements.map(\.id) == ["el_1", "el_3", "el_2"])
    doc.moveElement("el_1", by: -1)
    #expect(doc.elements.map(\.id) == ["el_1", "el_3", "el_2"])
  }

  @Test func repeatedIDsAreFound() {
    var doc = EditDocument()
    for _ in 0..<3 { doc.draw(onCanvas: box(0, 0, 100, 100)) }
    doc.elements[2].id = "el_1"
    #expect(doc.repeatedIDs == ["el_1"])
  }

  @Test func aNewDocumentStartsWithTheDefaultSentence() {
    #expect(EditDocument().prose == "Modify <ref_image_0> by: ")
    #expect(EditDocument.defaultProse.hasPrefix("Modify <ref_image_0> by:"))
  }

  @Test func clearingEmptiesTheBoxesAndRestoresTheSentence() {
    var doc = EditDocument()
    doc.prose = "Modify <ref_image_0> by: adding <el_1>"
    doc.draw(onCanvas: box(0, 0, 100, 100))
    doc.draw(onReference: "a.png", box: box(0, 0, 100, 100))
    doc.snapshot = EditSnapshot(prose: "x", descriptions: [:])
    doc.referenceIndex = 2
    doc.clear()
    #expect(doc.elements.isEmpty && doc.prose == EditDocument.defaultProse && doc.snapshot == nil && doc.referenceIndex == 0)
    // The ids start again from el_1.
    doc.draw(onCanvas: box(0, 0, 100, 100))
    #expect(doc.elements[0].id == "el_1" && doc.elements[0].colorIndex == 0)
  }

  @Test func theDocumentSurvivesCodable() throws {
    var doc = EditDocument()
    doc.prose = "Modify <ref_image_0>"
    doc.draw(onReference: "m1.png", box: box(250, 180, 820, 620))
    doc.draw(onCanvas: box(10, 20, 300, 400))
    let back = try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(doc))
    #expect(back == doc)
  }
}
