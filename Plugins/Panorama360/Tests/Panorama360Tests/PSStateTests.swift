import Foundation
import Testing

@testable import Panorama360

@MainActor
@Suite("State")
struct PSStateTests {
  @Test func nothingIsWrittenBeforeAProjectIsOpen() {
    let state = PSState()
    state.mutate { $0.description = "x" }
    #expect(state.doc.description == "x")
    #expect(state.projectFolder == nil)
  }

  @Test func everyChangeIsSavedInTheProjectFolder() {
    let folder = PSModelsTests.folder()
    let state = PSState()
    state.switchProject(folder: folder)
    state.mutate { $0.description = "a valley" }
    #expect(PanoState.load(from: folder).description == "a valley")
    state.doc.mode = .fast
    #expect(PanoState.load(from: folder).mode == .fast)
  }

  @Test func switchingProjectSwapsTheDocumentWithoutWritingIntoTheNewOne() throws {
    let first = PSModelsTests.folder()
    let second = PSModelsTests.folder()
    var other = PanoState()
    other.description = "second"
    try other.save(to: second)
    let state = PSState()
    state.switchProject(folder: first)
    state.mutate { $0.description = "first" }
    state.switchProject(folder: second)
    #expect(state.doc.description == "second")
    #expect(PanoState.load(from: first).description == "first")
    state.switchProject(folder: PSModelsTests.folder())
    #expect(state.doc == PanoState())
  }

  @Test func modelIsBaseReadsTheFileName() {
    let state = PSState()
    #expect(state.modelIsBase == nil)
    state.apply(context: Data(#"{"type":"context","tempFolder":"/tmp"}"#.utf8))
    #expect(state.modelIsBase == nil)
    state.apply(context: Data(#"{"type":"context","model":"flux_2_klein_base_9b_i8x.ckpt","tempFolder":"/tmp/t"}"#.utf8))
    #expect(state.modelIsBase == true)
    #expect(state.tempFolder == "/tmp/t")
    state.apply(context: Data(#"{"type":"context","model":"flux_2_klein_9b_q8p.ckpt","tempFolder":"/tmp/t"}"#.utf8))
    #expect(state.modelIsBase == false)
  }

  @Test func switchingProjectClearsWhatBelongedToTheOldOne() {
    let state = PSState(italian: false)
    state.switchProject(folder: PSModelsTests.folder())
    let sticker = Sticker(name: "s", file: "s.png")
    state.mutate { $0.stickers = [sticker] }
    state.setImage(TestImages.solid(10, 10, 1, 2, 3), for: sticker.id)
    state.previousDescription = "old project's text"
    state.error = "e"
    state.notice = "n"
    state.hasSent = true
    state.switchProject(folder: PSModelsTests.folder())
    #expect(state.previousDescription == nil && state.error == nil && state.notice == nil && !state.hasSent && !state.isDragging)
    #expect(state.image(for: sticker) == nil)
  }

  @Test func anImproveAnswerIsDroppedWhenTheTextChangedMeanwhile() async {
    let state = PSState(italian: false)
    state.mutate { $0.description = "a harbour" }
    await state.improve { _, _ in
      state.mutate { $0.description = "typed while waiting" }
      return .text("A quiet harbour at dawn, soft grey light and still water.")
    }
    #expect(state.doc.description == "typed while waiting" && state.previousDescription == nil && state.error != nil)
  }

  @Test func anImproveAnswerIsDroppedWhenTheProjectChangedMeanwhile() async throws {
    let first = PSModelsTests.folder(), second = PSModelsTests.folder()
    let state = PSState(italian: false)
    state.switchProject(folder: first)
    state.mutate { $0.description = "a harbour" }
    await state.improve { _, _ in
      state.switchProject(folder: second)
      return .text("A quiet harbour at dawn, soft grey light and still water.")
    }
    #expect(state.doc.description == "" && state.previousDescription == nil)
    #expect(PanoState.load(from: second).description == "")
    #expect(PanoState.load(from: first).description == "a harbour")
  }
}
