import Foundation
import SwiftUI
import Testing

@testable import PromptMasterF3

@MainActor
struct FieldBindingTests {
  func makeState() -> F3State {
    F3State(
      promptFolder: F3Prompts.folder(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
      store: F3Store(storage: MemoryStorage()), italian: true, shuffler: { _, _ in [] }, sleep: { _ in try? await Task.sleep(for: .seconds(3600)) })
  }

  @Test func aFieldReadsTheCurrentTextEvenWhenTheCardHoldsAStaleCopy() {
    let state = makeState()
    state.compositionChanged("a woman <woman_1>")
    state.commitComposition()
    let stale = state.document.elements[0]  // la copia con cui la scheda è stata disegnata
    let desc = state.elementBinding("woman_1", \.desc, fallback: stale.desc)
    desc.wrappedValue = "una donna"
    state.update(element: "woman_1") { $0.desc = "una donna in nero" }  // un'altra battuta: la copia non è ancora ridisegnata
    #expect(stale.desc == "")
    // Legge dallo stato, non dalla copia: una copia in ritardo ridà all'editor il testo di prima e il cursore salta in fondo.
    #expect(desc.wrappedValue == "una donna in nero")
    desc.wrappedValue = "una donna in nero con ombrello"
    #expect(state.document.elements[0].desc == "una donna in nero con ombrello")
    let box = state.elementBinding("woman_1", \.box, fallback: stale.box)
    let moved = BBox(y0: 100, x0: 100, y1: 500, x1: 500)
    box.wrappedValue = moved
    #expect(state.document.elements[0].box == moved && box.wrappedValue == moved)
    state.compositionChanged("")  // l'id sparisce dal testo: l'elemento va via
    state.commitComposition()
    #expect(state.elementBinding("woman_1", \.desc, fallback: "x").wrappedValue == "x")
  }
}
