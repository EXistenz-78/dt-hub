import Foundation
import Testing

@testable import PromptMasterMOSS

@MainActor
struct SnapshotTests {
  static let data = MossData.load(folder: URL(fileURLWithPath: "/nonexistent/DT Hub"))

  func state() -> MossState {
    let state = MossState(
      data: Self.data,
      promptFolder: MossPrompts.folder(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent("moss-snap-\(UUID().uuidString)")),
      store: MossStore(storage: MemoryStorage()), italian: false, shuffler: { _, _ in [] })
    state.active = true
    return state
  }

  var lightID: String { Self.data.database.categories.first { $0.id == "light_source" }!.terms[0].id }
  var genreID: String { Self.data.database.categories.first { $0.id == "photo_genre" }!.terms[0].id }

  func filled(_ state: MossState) {
    state.document.description = "una foresta"
    state.document.selection = [lightID, genreID]
    state.document.freeMeta = ["foresta"]
    state.addItem(label: .text, box: FracBox(x0: 0.1, y0: 0.1, x1: 0.5, y1: 0.5))
    state.update(item: 1) {
      $0.caption = "scritta"
      $0.text = "Kyoto"
      $0.tags = "bianco"
      $0.colors = ["#FFFFFF"]
    }
  }

  func result(_ rewrites: [MossRewrite]) -> MossWriteResult { MossWriteResult(rewrites: rewrites, status: "done", request: "r", answer: "a") }

  @Test func applyReplacesTheTextsAndTouchesNothingElse() {
    let state = state()
    filled(state)
    let before = state.document
    state.apply(result([
      MossRewrite(kind: .summary, original: "una foresta", text: "A forest."),
      MossRewrite(kind: .item(id: 1, label: .text), original: "scritta", text: "White lettering."),
      MossRewrite(kind: .meta, original: "foresta", text: "forest, woods"),
      MossRewrite(kind: .tags(id: 1), original: "bianco", text: "white"),
    ]))
    #expect(state.document.description == "A forest.")
    #expect(state.document.freeMeta == ["forest", "woods"])
    #expect(state.document.items[0].caption == "White lettering." && state.document.items[0].tags == "white")
    // intatti: il testo verbatim, la posizione, i colori, il tipo
    #expect(state.document.items[0].text == "Kyoto" && state.document.items[0].box == before.items[0].box)
    #expect(state.document.items[0].colors == ["#FFFFFF"] && state.document.items[0].label == .text)
    // le voci della caption sono ormai nel testo; quelle di meta restano
    #expect(state.document.selection == [genreID])
    #expect(state.document.snapshot?.description == "una foresta")
  }

  @Test func aTextChangedWhileWritingIsKept() {
    let state = state()
    filled(state)
    state.document.description = "una foresta di notte"  // cambiata mentre l'LLM scriveva
    state.apply(result([MossRewrite(kind: .summary, original: "una foresta", text: "A forest.")]))
    #expect(state.document.description == "una foresta di notte")
    #expect(state.document.snapshot == nil)
    #expect(state.status.contains("summary"))
  }

  @Test func undoRestoresTheTextsOfTheLastWriteOnly() {
    let state = state()
    filled(state)
    state.apply(result([MossRewrite(kind: .summary, original: "una foresta", text: "A forest.")]))
    state.apply(result([MossRewrite(kind: .summary, original: "A forest.", text: "A wood.")]))
    #expect(state.document.snapshot?.description == "A forest.")  // solo l'ultima
    state.undo()
    #expect(state.document.description == "A forest.")
    #expect(state.document.snapshot == nil && !state.canUndo)
  }

  @Test func restoreBringsBackSelectionMetaCaptionsAndTagsAndIgnoresDeletedItems() {
    let state = state()
    filled(state)
    state.apply(result([
      MossRewrite(kind: .summary, original: "una foresta", text: "A forest."),
      MossRewrite(kind: .item(id: 1, label: .text), original: "scritta", text: "Lettering."),
      MossRewrite(kind: .tags(id: 1), original: "bianco", text: "white"),
    ]))
    state.removeItem(1)  // nel frattempo l'elemento sparisce
    state.undo()
    #expect(state.document.description == "una foresta")
    #expect(state.document.selection == [lightID, genreID])
    #expect(state.document.items.isEmpty)
  }

  @Test func undoPutsBackCaptionAndTagsOfAnItemThatStillExists() {
    let state = state()
    filled(state)
    state.apply(result([
      MossRewrite(kind: .item(id: 1, label: .text), original: "scritta", text: "Lettering."),
      MossRewrite(kind: .tags(id: 1), original: "bianco", text: "white"),
    ]))
    state.undo()
    #expect(state.document.items[0].caption == "scritta" && state.document.items[0].tags == "bianco")
  }

  @Test func canWriteNeedsSomethingToWriteAndAnActiveIdleTab() {
    let state = state()
    #expect(!state.canWrite)
    state.document.description = "x"
    #expect(state.canWrite)
    state.isWriting = true
    #expect(!state.canWrite)
  }
}
