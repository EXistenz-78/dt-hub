import Foundation
import Testing

@testable import Flux3Editing

struct PicturePlanTests {
  private func box(_ y0: Int, _ x0: Int, _ y1: Int, _ x1: Int) -> BBox { BBox(y0: y0, x0: x0, y1: y1, x1: x1) }
  private func ref(_ number: Int, _ name: String) -> RefImage { RefImage(number: number, path: "/p/\(name)", size: CGSize(width: 800, height: 600)) }

  /// Un documento con un elemento di ogni tipo: el_1 da riferimento (a.png), el_2 esistente, el_3 spostato, el_4 tolto, el_5 nuovo.
  private func document() -> EditDocument {
    var doc = EditDocument()
    doc.draw(onReference: "a.png", box: box(100, 100, 400, 400))
    for _ in 0..<4 { doc.draw(onCanvas: box(500, 500, 700, 700)) }
    doc.setKind(.existing, of: "el_2")
    doc.setKind(.move, of: "el_3")
    doc.setKind(.remove, of: "el_4")
    return doc
  }

  @Test func theStartPictureComesFirstWithABoxForEveryKindOfElement() {
    let doc = document()
    let plan = EditPictures.plan(document: doc, refs: [ref(1, "a.png")], hasStartImage: true)
    let start = plan.pictures[0]
    #expect(start.number == 0 && start.role == .start)
    #expect(start.boxes.map(\.id) == ["el_1", "el_2", "el_3", "el_3", "el_4", "el_5"])
    #expect(start.boxes.map(\.style) == [.solid, .solid, .dashedFrom, .solid, .dashedRemoved, .solid])
    #expect(start.boxes[0].box == doc.elements[0].tgt)  // da riferimento: la destinazione sul canvas
    #expect(start.boxes[1].box == doc.elements[1].src)  // esistente: dov'è
    #expect(start.boxes[2].box == doc.elements[2].src && start.boxes[3].box == doc.elements[2].tgt)  // spostato: origine e destinazione
    #expect(start.boxes[4].box == doc.elements[3].src)  // tolto: dov'era
    #expect(start.boxes[5].box == doc.elements[4].tgt)  // nuovo: dove va
    #expect(start.boxes.map(\.colorIndex) == [0, 1, 2, 2, 3, 4])
  }

  @Test func aReferencePictureShowsTheSourceBoxesOfTheElementsThatTakeFromIt() {
    let plan = EditPictures.plan(document: document(), refs: [ref(1, "a.png")], hasStartImage: true)
    #expect(plan.pictures.map(\.number) == [0, 1])
    let reference = plan.pictures[1]
    #expect(reference.role == .reference && reference.boxes.map(\.id) == ["el_1"] && reference.boxes[0].style == .solid)
    #expect(reference.boxes[0].box == document().elements[0].src)
  }

  @Test func onlyTheReferencesThatAreUsedGoAlong_inOrderOfTheirNumber() {
    var doc = EditDocument()
    doc.draw(onReference: "c.png", box: box(0, 0, 300, 300))
    doc.draw(onReference: "a.png", box: box(0, 0, 300, 300))
    let refs = [ref(1, "a.png"), ref(2, "b.png"), ref(3, "c.png")]
    let plan = EditPictures.plan(document: doc, refs: refs, hasStartImage: true)
    #expect(plan.pictures.map(\.number) == [0, 1, 3])
    #expect(plan.dropped.isEmpty)
  }

  @Test func withoutAStartImageThereIsNoPictureZero() {
    let plan = EditPictures.plan(document: document(), refs: [ref(1, "a.png")], hasStartImage: false)
    #expect(plan.pictures.map(\.number) == [1])
  }

  @Test func theStartPictureGoesAlongEvenWithoutBoxes_noElementsNoReferences() {
    let plan = EditPictures.plan(document: EditDocument(), refs: [], hasStartImage: true)
    #expect(plan.pictures.count == 1 && plan.pictures[0].boxes.isEmpty)
    #expect(EditPictures.plan(document: EditDocument(), refs: [], hasStartImage: false).pictures.isEmpty)
  }

  @Test func aCapKeepsTheStartAndTheFirstReferencesAndNamesTheOnesLeftOut() {
    var doc = EditDocument()
    var refs: [RefImage] = []
    for number in 1...5 {
      doc.draw(onReference: "r\(number).png", box: box(0, 0, 300, 300))
      refs.append(ref(number, "r\(number).png"))
    }
    let plan = EditPictures.plan(document: doc, refs: refs, hasStartImage: true, maxPictures: 3)
    #expect(plan.pictures.map(\.number) == [0, 1, 2])
    #expect(plan.dropped == [3, 4, 5])
    #expect(EditPictures.maxPictures == 6)
  }

  @Test func theCaptionOfABoxSaysWhatItIs() {
    func caption(_ style: OverlayBox.Style) -> String { OverlayBox(id: "el_1", colorIndex: 0, box: box(0, 0, 10, 10), style: style).caption }
    #expect(caption(.solid) == "el_1")
    #expect(caption(.dashedFrom) == "el_1 (from)")
    #expect(caption(.dashedRemoved) == "el_1 (removed)")
  }
}
