import Foundation
import Testing

@testable import Flux3Editing

@MainActor
struct PupStateTests {
  private func box(_ y0: Int, _ x0: Int, _ y1: Int, _ x1: Int) -> BBox { BBox(y0: y0, x0: x0, y1: y1, x1: x1) }

  private func state() -> EditState {
    let s = EditState(store: EditStore(storage: MemoryStorage()), italian: false)
    s.document.draw(onCanvas: box(10, 10, 200, 200))
    s.document.elements[0].desc = "old"
    s.document.prose = "Modify <ref_image_0> by adding <el_1>."
    return s
  }

  private let person = PupRow(id: "person_1", from: "ref_image_0", src: [313, 468, 1000, 833], tgt: [313, 468, 1000, 833], desc: "A woman")

  private func result(prose: String = "Add <el_1>.", desc: String = "A new thing", rows: [PupRow]? = nil) -> EditPupResult {
    EditPupResult(
      prose: prose, descriptions: ["el_1": desc], extraRows: rows ?? [person], status: "", request: "r", answer: "a", succeeded: true)
  }

  @Test func extraRowsAreOptionalInTheFile() throws {
    let old = try JSONDecoder().decode(EditDocument.self, from: Data(#"{"prose":"x","elements":[],"referenceIndex":0}"#.utf8))
    #expect(old.extraRows == nil)
    let new = try JSONDecoder().decode(
      EditDocument.self,
      from: Data(#"{"prose":"x","elements":[],"referenceIndex":0,"extraRows":[{"id":"p","from":"target","tgt":{"y0":1,"x0":2,"y1":30,"x1":40},"desc":"d"}]}"#.utf8))
    #expect(new.extraRows?.map(\.id) == ["p"])
  }

  @Test func composerAppendsExtraRowsAfterOurElements() {
    let s = state()
    s.applyPup(result(), original: EditSnapshot.take(from: s.document))
    let text = s.sendText
    let ours = text.range(of: "\"id\": \"el_1\""), extra = text.range(of: "\"id\": \"person_1\"")
    #expect(ours != nil && extra != nil && ours!.lowerBound < extra!.lowerBound)
    #expect(text.contains("\"from\": \"ref_image_0\"") && text.contains("[313, 468, 1000, 833]"))
  }

  @Test func applyPupWritesProseDescriptionsAndRows() {
    let s = state()
    s.applyPup(result(), original: EditSnapshot.take(from: s.document))
    #expect(s.document.prose == "Add <el_1>." && s.document.elements[0].desc == "A new thing")
    #expect(s.document.extraRows?.map(\.id) == ["person_1"] && s.document.extraRows?[0].src == box(313, 468, 1000, 833))
    #expect(s.document.snapshot != nil)
  }

  @Test func applyPupKeepsWhatTheUserChangedMeanwhile() {
    let s = state()
    let original = EditSnapshot.take(from: s.document)
    s.document.elements[0].desc = "typed while waiting"
    s.applyPup(result(), original: original)
    #expect(s.document.elements[0].desc == "typed while waiting")
    #expect(s.document.prose == "Add <el_1>.")
    #expect(!s.status.isEmpty)
  }

  @Test func undoRestoresProseDescriptionsAndRows() {
    let s = state()
    s.applyPup(result(), original: EditSnapshot.take(from: s.document))
    s.undo()
    #expect(s.document.prose == "Modify <ref_image_0> by adding <el_1>." && s.document.elements[0].desc == "old")
    #expect(s.document.extraRows == nil)
  }

  @Test func removeExtraRowTakesItOutOfTheText() {
    let s = state()
    s.applyPup(result(), original: EditSnapshot.take(from: s.document))
    s.removeExtraRow("person_1")
    #expect(s.document.extraRows == nil && !s.sendText.contains("person_1"))
  }

  @Test func aFailedPupResultChangesNothing() {
    let s = state()
    let before = s.document
    s.applyPup(EditPupResult.failed(status: "No answer."), original: EditSnapshot.take(from: s.document))
    #expect(s.document == before && s.status == "No answer.")
  }

  @Test func aNewRunReplacesTheOldRows() {
    let s = state()
    s.applyPup(result(), original: EditSnapshot.take(from: s.document))
    let other = PupRow(id: "tree_1", from: "ref_image_0", src: [1, 1, 500, 500], tgt: [1, 1, 500, 500], desc: "A tree")
    s.applyPup(result(prose: "Again <el_1>.", rows: [other]), original: EditSnapshot.take(from: s.document))
    #expect(s.document.extraRows?.map(\.id) == ["tree_1"])
  }
}
