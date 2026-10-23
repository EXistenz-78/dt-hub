import Foundation
import SwiftUI
import Testing

@testable import PromptMasterI4

@MainActor
@Suite("The text fields of an element card")
struct FieldBindingTests {
  private func state() -> I4State {
    let state = I4State(
      data: I4Data(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig, warnings: []),
      store: I4Store(storage: MemoryStorage()), italian: false)
    state.active = true
    return state
  }

  @Test func aFieldReadsTheCurrentTextEvenWhenTheCardHoldsAStaleCopy() {
    let state = state()
    state.addElement(.text)
    let id = state.document.elements[0].id
    let stale = state.document.elements[0]  // the copy the card was drawn with
    let desc = state.elementBinding(id, \.desc, fallback: stale.desc)
    desc.wrappedValue = "one"
    state.document.updateElement(id) { $0.desc = "one two" }  // another keystroke: the card's copy is not redrawn yet
    #expect(stale.desc == "")
    // It reads the state, not the copy: a stale read hands the editor the old text and the cursor jumps to the end.
    #expect(desc.wrappedValue == "one two")
    desc.wrappedValue = "one two three"
    #expect(state.document.elements[0].desc == "one two three")
    let printed = state.elementBinding(id, \.text, fallback: stale.text)
    printed.wrappedValue = "OPEN"
    #expect(state.document.elements[0].text == "OPEN")
    state.removeElement(id)  // the element is gone: it falls back to the copy, no crash
    #expect(state.elementBinding(id, \.desc, fallback: "x").wrappedValue == "x")
  }
}
