import Foundation
import Testing

@testable import Flux3Editing

struct BriefPicturesTests {
  private func box(_ y0: Int, _ x0: Int, _ y1: Int, _ x1: Int) -> BBox { BBox(y0: y0, x0: x0, y1: y1, x1: x1) }
  private let refs = [RefImage(number: 1, path: "/p/a.png", size: CGSize(width: 800, height: 600))]

  /// el_1 da riferimento (a.png), el_2 nuovo, el_3 esistente, el_4 spostato, el_5 tolto.
  private func document() -> EditDocument {
    var doc = EditDocument()
    doc.draw(onReference: "a.png", box: box(100, 100, 400, 400))
    for _ in 0..<4 { doc.draw(onCanvas: box(500, 500, 700, 700)) }
    doc.setKind(.existing, of: "el_3")
    doc.setKind(.move, of: "el_4")
    doc.setKind(.remove, of: "el_5")
    for index in doc.elements.indices { doc.elements[index].desc = "x" }
    return doc
  }

  private func parts(_ doc: EditDocument) -> [EditPart] { EditBrief.parts(from: doc) }
  private let both = [
    EditPicture(number: 0, role: .start, path: "/t/s.png"), EditPicture(number: 1, role: .reference, path: "/t/r1.png"),
  ]

  @Test func eachContextLineSaysInWhichPictureTheBoxIs() {
    let doc = document()
    let lines = EditBrief.context(for: parts(doc), in: doc, refs: refs, pictures: both)
    #expect(lines == [
      "el_1: an object taken from <ref_image_1> (source box in picture 2, destination box in picture 1)",
      "el_2: a new object to describe in rich visual detail (destination box in picture 1)",
      "el_3: already in <ref_image_0>; kept in place, or changed as its description says (box in picture 1)",
      "el_4: already in <ref_image_0>; moved to another place (dashed box = where it is, solid box = where it goes, in picture 1)",
      "el_5: already in <ref_image_0>; removed (dashed box in picture 1)",
    ])
  }

  @Test func withoutPicturesTheContextIsAsBefore() {
    let doc = document()
    let lines = EditBrief.context(for: parts(doc), in: doc, refs: refs)
    #expect(lines[0] == "el_1: an object taken from <ref_image_1>")
    #expect(lines[1] == "el_2: a new object to describe in rich visual detail")
    #expect(lines[4] == "el_5: already in <ref_image_0>; removed")
  }

  @Test func aReferencePictureLeftOutIsNotNamedAsSource_aMissingStartPictureHasNoDestination() {
    let doc = document()
    let onlyStart = EditBrief.context(for: parts(doc), in: doc, refs: refs, pictures: [both[0]])
    #expect(onlyStart[0] == "el_1: an object taken from <ref_image_1> (destination box in picture 1)")
    let onlyReference = EditBrief.context(for: parts(doc), in: doc, refs: refs, pictures: [both[1]])
    #expect(onlyReference[0] == "el_1: an object taken from <ref_image_1> (source box in picture 1)")
    #expect(onlyReference[1] == "el_2: a new object to describe in rich visual detail")
  }

  @Test func theLegendListsThePicturesInOrderAndForbidsMentioningThem() {
    let doc = document()
    let message = EditBrief.message(parts(doc), pictures: both)
    #expect(message.contains("""
      Attached pictures, in order (boxes drawn on them, in the colour of each element and labelled with its id, show where the elements are; use them to understand the scene and each element, and never mention the pictures or the boxes in your answer):
      - picture 1: <ref_image_0>, the picture being edited, shown as the canvas of the result
      - picture 2: <ref_image_1>, a reference picture
      """))
    #expect(!EditBrief.message(parts(doc)).contains("Attached pictures"))
  }

  @Test func theLegendComesBeforeTheBlocksAndAfterTheContext() {
    let doc = document()
    let message = EditBrief.message(parts(doc), context: EditBrief.context(for: parts(doc), in: doc, refs: refs, pictures: both), pictures: both)
    let context = message.range(of: "Context (")!.lowerBound, legend = message.range(of: "Attached pictures")!.lowerBound
    let blocks = message.range(of: "## element: el_1")!.lowerBound
    #expect(context < legend && legend < blocks)
  }
}
