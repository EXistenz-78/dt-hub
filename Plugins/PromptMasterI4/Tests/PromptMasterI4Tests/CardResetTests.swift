import Foundation
import Testing

@testable import PromptMasterI4

@MainActor
@Suite("Clearing the two cards")
struct CardResetTests {
  private func state() -> I4State {
    let state = I4State(
      data: I4Data(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig, warnings: []),
      store: I4Store(storage: MemoryStorage()), italian: false)
    state.active = true
    return state
  }

  private func filled() -> I4State {
    let state = state()
    state.document.description = "una scena"
    state.document.background = "una strada"
    state.document.addColor("#112233")
    for id in ["ls_neon", "mo_peaceful", "fr_closeup", "bg_blurred", "md_3d_render"] { state.choose(id) }
    state.addElement(.obj)
    state.addElement(.text)
    state.select(state.document.elements[0].id)
    state.document.updateElement(state.document.elements[0].id) { $0.desc = "una tazza" }
    return state
  }

  @Test func theGeneralCardEmptiesItsTextTermsColorsAndBackgroundAndLeavesTheModeAndTheElements() {
    let state = filled()
    state.setMode(.art)
    state.document.written["description"] = WrittenPhrase(text: "A scene.", input: "una scena")
    #expect(state.hasGeneralContent)
    state.clearGeneral()
    let document = state.document
    #expect(document.description.isEmpty && document.selection.isEmpty && document.colors.isEmpty && document.background.isEmpty)
    #expect(document.mode == .art && document.elements.count == 2 && document.elements[0].desc == "una tazza")
    #expect(document.written.isEmpty)  // its sentences went with its content
    #expect(!state.hasGeneralContent)
  }

  @Test func theElementsCardRemovesEveryElementTheirSelectionAndTheirOpenCardsAndLeavesTheGeneralCard() {
    let state = filled()
    let id = state.document.elements[0].id
    state.document.written[I4FieldInfo.elementID(id)] = WrittenPhrase(text: "A cup.", input: "object\nuna tazza")
    #expect(state.hasElements)
    state.clearElements()
    #expect(state.document.elements.isEmpty && state.selectedElement == nil && state.expandedElements.isEmpty)
    #expect(state.document.description == "una scena" && state.document.selection.count == 5)
    #expect(state.document.written.isEmpty && !state.hasElements)
    // Ids are never reused, so a sentence cannot come back to a new element.
    state.addElement(.obj)
    #expect(state.document.elements[0].id != id)
  }

  @Test func theButtonsAreOffWhenThereIsNothingToClearOrWhileTheModelWrites() {
    let state = state()
    #expect(!state.canClearGeneral && !state.canClearElements)
    let full = filled()
    #expect(full.canClearGeneral && full.canClearElements)
    full.beginWriting()
    #expect(!full.canClearGeneral && !full.canClearElements)
  }

  @Test func aJSONEditedByHandIsNotTouchedByEitherReset() {
    let state = filled()
    state.editJSON("{ \"mine\": 1 }")
    state.clearGeneral()
    state.clearElements()
    #expect(state.hasEditedJSON && state.jsonText == "{ \"mine\": 1 }")
  }

  @Test func theWordsOfTheGeneralCardAreGeneral() {
    #expect(L.text(.title, italian: true) == "Generale" && L.text(.title, italian: false) == "General")
  }
}
