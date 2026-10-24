import Foundation
import Testing

@testable import PromptMasterF3

@MainActor
struct PupStateTests {
  func makeState() -> F3State {
    F3State(
      promptFolder: F3Prompts.folder(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
      store: F3Store(storage: MemoryStorage()), italian: false, shuffler: { _, _ in [] }, sleep: { _ in try? await Task.sleep(for: .seconds(3600)) })
  }

  func prepared() -> F3State {
    let s = makeState()
    s.document = PupWriterTests().document()
    s.document.selection = ["any-term"]
    s.compositionChanged(s.document.composition)
    s.commitComposition()
    return s
  }

  func result(descriptions: [String: String] = ["lantern_1": "A mossy lantern.", "cat_1": "A black cat."], added: [PupRow]? = nil) -> F3PupResult {
    F3PupResult(
      caption: "A woman <person_1> with a lantern <lantern_1> and a cat <cat_1>.", descriptions: descriptions,
      addedRows: added ?? [PupRow(id: "person_1", bbox: [245, 245, 925, 650], desc: "A woman in a blue blouse.")], status: "", request: "r", answer: "a",
      succeeded: true)
  }

  @Test func applyPupFoldsTheDescriptionAndTheTermsIntoTheCompositionAndUpdatesTheElements() {
    let s = prepared()
    s.applyPup(result(), original: F3Snapshot.take(from: s.document))
    #expect(s.document.description.isEmpty && s.document.selection.isEmpty)
    #expect(s.document.composition == "A woman <person_1> with a lantern <lantern_1> and a cat <cat_1>.")
    #expect(s.document.element("lantern_1")?.desc == "A mossy lantern." && s.document.element("lantern_1")?.box == BBox(y0: 389, x0: 807, y1: 991, x1: 956))
    #expect(s.document.snapshot != nil)
  }

  @Test func anAddedRowBecomesAnElementWithTheModelsBoxAndDesc() {
    let s = prepared()
    s.applyPup(result(), original: F3Snapshot.take(from: s.document))
    let person = s.document.element("person_1")
    #expect(person?.box == BBox(y0: 245, x0: 245, y1: 925, x1: 650) && person?.desc == "A woman in a blue blouse.")
  }

  @Test func undoRestoresTheTextsAndTakesTheAddedElementsAway() {
    let s = prepared()
    let before = s.document
    s.applyPup(result(), original: F3Snapshot.take(from: s.document))
    s.undo()
    #expect(s.document.description == before.description && s.document.selection == before.selection && s.document.composition == before.composition)
    #expect(s.document.element("person_1") == nil && s.document.element("lantern_1")?.desc == "una lanterna di pietra con muschio")
  }

  @Test func whatTheUserChangedMeanwhileIsKept() {
    let s = prepared()
    let original = F3Snapshot.take(from: s.document)
    s.document.composition = "typed while waiting <lantern_1> <cat_1>"
    s.applyPup(result(), original: original)
    #expect(s.document.composition == "typed while waiting <lantern_1> <cat_1>" && s.document.element("person_1") == nil && !s.status.isEmpty)
  }

  @Test func aFailedResultChangesNothing() {
    let s = prepared()
    let before = s.document
    s.applyPup(F3PupResult.failed(status: "No answer."), original: F3Snapshot.take(from: s.document))
    #expect(s.document == before && s.status == "No answer.")
  }
}
