import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterI4

@MainActor
@Suite("The state while the language model writes")
struct WritingStateTests {
  private func state(_ storage: MemoryStorage = MemoryStorage()) -> I4State {
    let state = I4State(
      data: I4Data(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig, warnings: []),
      store: I4Store(storage: storage), italian: false)
    state.active = true
    return state
  }

  @Test func theButtonNeedsSomethingToWriteAndNothingElseRunning() {
    let state = state()
    #expect(!state.canWrite)
    state.document.description = "una scena"
    #expect(state.canWrite)
    state.isWriting = true
    #expect(!state.canWrite && !state.canSend)
    state.isWriting = false
    state.isSending = true
    #expect(!state.canWrite)
    state.isSending = false
    state.active = false
    #expect(!state.canWrite)
  }

  @Test func theOptionsAndTheSystemPromptComeFromTheConfiguration() {
    let state = state()
    let options = state.writeOptions
    #expect(options.temperature == 0.6 && options.maxTokens == 4096 && options.thinking == false && options.timeout == 600)
    #expect(state.writeSystem == I4Data.embeddedConfig.system && state.writeSystem.contains("<already_written>"))
  }

  @Test func theSentencesAreKeptAcrossRunsAndSpentOnesGoWhenTheFieldEmpties() {
    let storage = MemoryStorage()
    let first = state(storage)
    first.document.description = "una scena"
    let input = first.fields.first { $0.id == "description" }!.input
    first.apply(I4Writer.Outcome(phrases: ["description": WrittenPhrase(text: "A scene.", input: input), "lighting": WrittenPhrase(text: "gone", input: "x")], status: "1 sentence(s) written."))
    #expect(first.document.written.keys.sorted() == ["description"])  // the lighting one had nothing to write from
    let again = state(storage)
    #expect(again.document.written["description"]?.text == "A scene." && again.document.caption(catalog: again.catalog).description == "A scene.")
    #expect(first.status == "1 sentence(s) written.")
  }

  @Test func newSentencesReplaceTheJSONEditedByHandAndSayso() {
    let state = state()
    state.document.description = "una scena"
    state.editJSON("{ \"mine\": 1 }")
    state.beginWriting()
    state.apply(I4Writer.Outcome(phrases: ["description": WrittenPhrase(text: "A scene.", input: state.fields[0].input)], status: "1 sentence(s) written."))
    #expect(!state.hasEditedJSON && state.status == "1 sentence(s) written. The JSON you edited by hand was replaced.")
  }

  @Test func aJSONEditMadeWhileTheModelWritesIsKeptAndSaid() {
    let state = state()
    state.document.description = "una scena"
    state.editJSON("{ \"first\": 1 }")
    state.beginWriting()
    #expect(state.isWriting && !state.canSend)
    state.editJSON("{ \"first\": 1, \"second\": 2 }")  // the user went on while the model worked
    state.apply(I4Writer.Outcome(phrases: ["description": WrittenPhrase(text: "A scene.", input: state.fields[0].input)], status: "1 sentence(s) written."))
    #expect(state.hasEditedJSON && state.jsonText == "{ \"first\": 1, \"second\": 2 }")
    #expect(state.status == "1 sentence(s) written. The JSON you edited while it wrote was kept.")
    // Edited for the first time while it wrote: kept too.
    let other = self.state()
    other.document.description = "una scena"
    other.beginWriting()
    other.editJSON("{ \"late\": 1 }")
    other.apply(I4Writer.Outcome(phrases: ["description": WrittenPhrase(text: "A scene.", input: other.fields[0].input)], status: "x"))
    #expect(other.hasEditedJSON)
  }

  @Test func ifNothingWasWrittenTheJSONEditedByHandStays() {
    let state = state()
    state.document.description = "una scena"
    state.editJSON("{ \"mine\": 1 }")
    state.apply(I4Writer.Outcome(phrases: [:], failed: ["High level description"], status: "No language model chosen."))
    #expect(state.hasEditedJSON && state.jsonText == "{ \"mine\": 1 }" && state.status == "No language model chosen.")
  }

  @Test func theTableShowsEveryFieldWithItsStateInTheOrderOfTheCaption() {
    let state = state()
    state.document.description = "una scena"
    #expect(state.fields.map(\.state) == [.raw, .empty, .empty, .empty, .empty, .empty])
    #expect(state.fieldsToWrite.map(\.id) == ["description"])
  }
}
