import Foundation
import Testing

@testable import PromptMasterI4

@MainActor
@Suite("The state of the tab")
struct StateTests {
  private func defaults() -> UserDefaults { UserDefaults(suiteName: "i4-state-\(UUID().uuidString)")! }

  private func state(
    defaults: UserDefaults? = nil, data: I4Data = I4Data(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig, warnings: []),
    shuffled: Set<String> = ["fr_closeup", "lq_soft"]
  ) -> I4State {
    let state = I4State(
      data: data, store: I4Store(defaults: defaults ?? self.defaults()), italian: true, shuffler: { _, _ in shuffled },
      colorMaker: { "#ABCDEF" })
    state.active = true
    return state
  }

  @Test func theFirstRunStartsEmptyWithTheCaptionOfNothing() {
    let state = state()
    #expect(state.document == I4Document() && state.status.isEmpty && !state.hasEditedJSON)
    #expect(state.jsonText == state.generatedJSON && state.generatedJSON.contains("\"elements\": []"))
  }

  @Test func choosingATermIsRememberedAndFollowsTheRulesOfTheLists() {
    let store = defaults()
    let first = state(defaults: store)
    first.choose("fr_closeup")
    first.choose("fr_wide")
    #expect(first.isChosen("fr_wide") && !first.isChosen("fr_closeup"))
    first.setMode(.art)
    #expect(first.document.selection.isEmpty)  // Framing is Photo only
    let again = state(defaults: store)
    #expect(again.document == first.document && again.document.mode == .art)
  }

  @Test func theShuffleReplacesTheSelectionWithWhatTheShufflerPicks() {
    let state = state()
    state.choose("ls_neon")
    state.shuffle()
    #expect(state.document.selection == ["fr_closeup", "lq_soft"])
  }

  @Test func theRandomColorIsAddedToTheStyleAndToAnElementWithTheirLimits() {
    let state = state()
    for _ in 0..<20 { state.addColor() }
    #expect(state.document.colors.count == 16 && state.document.colors.allSatisfy { $0 == "#ABCDEF" })
    state.addElement()
    let id = state.document.elements[0].id
    for _ in 0..<9 { state.addColor(toElement: id) }
    #expect(state.document.elements[0].colors.count == 5)
  }

  @Test func aNewElementOpensAndARemovedOneIsForgotten() {
    let state = state()
    state.addElement()
    let id = state.document.elements[0].id
    #expect(state.expandedElements == [id])
    state.toggleExpanded(id)
    #expect(state.expandedElements.isEmpty)
    state.toggleExpanded(id)
    state.removeElement(id)
    #expect(state.document.elements.isEmpty && state.expandedElements.isEmpty)
  }

  @Test func theSectionsAndCategoriesOpenAndCloseAndAreRemembered() {
    let store = defaults()
    let first = state(defaults: store)
    first.toggleOpen(section: "lighting")
    first.toggleOpen(category: "light_source")
    first.toggleOpen(category: "light_source")
    first.toggleOpen(category: "framing")
    let again = state(defaults: store)
    #expect(again.isOpen(section: "lighting") && again.isOpen(category: "framing") && !again.isOpen(category: "light_source"))
  }

  // MARK: The JSON edited by hand

  @Test func aTextChangedByHandIsWhatIsSentAndRestoringBringsBackTheFields() {
    let state = state()
    state.document.description = "a diner"
    let generated = state.generatedJSON
    state.editJSON(generated + "\n")
    #expect(state.hasEditedJSON && state.jsonText == generated + "\n")
    state.restoreJSON()
    #expect(!state.hasEditedJSON && state.jsonText == generated)
  }

  @Test func aTextEqualToTheCaptionOfTheFieldsIsNoEditAtAll() {
    let state = state()
    state.editJSON("hand written")
    #expect(state.hasEditedJSON)
    state.editJSON(state.generatedJSON)
    #expect(!state.hasEditedJSON)
  }

  @Test func changingAFieldDoesNotTouchTheTextEditedByHandAndItIsRemembered() {
    let store = defaults()
    let first = state(defaults: store)
    first.editJSON("{\"mine\": true}")
    first.document.description = "changed after"
    #expect(first.jsonText == "{\"mine\": true}" && first.generatedJSON.contains("changed after"))
    let again = state(defaults: store)
    #expect(again.jsonText == "{\"mine\": true}" && again.hasEditedJSON)
  }

  // MARK: Reading what was saved

  @Test func aSessionOfAnotherLayoutOrGarbageStartsEmpty() throws {
    let store = defaults()
    var session = I4Session()
    session.document.description = "old"
    session.schema = 99
    store.set(try JSONEncoder().encode(session), forKey: I4Store.key)
    #expect(state(defaults: store).document == I4Document())
    store.set(Data("garbage".utf8), forKey: I4Store.key)
    #expect(state(defaults: store).document == I4Document())
  }

  @Test func choicesNoLongerInTheVocabularyOrNotShownInTheModeAreDroppedAtStart() throws {
    let store = defaults()
    var session = I4Session()
    session.document.mode = .art
    session.document.selection = ["fr_closeup", "gone_forever", "lq_soft"]
    store.set(try JSONEncoder().encode(session), forKey: I4Store.key)
    #expect(state(defaults: store).document.selection == ["lq_soft"])
  }

  @Test func warningsAboutTheDataFilesAndMissingCategoriesAreShownInTheStatusLine() {
    var config = I4Data.embeddedConfig
    config.fields["lighting"]?.common = ["light_source", "no_such_category"]
    let data = I4Data(database: I4Data.embeddedDatabase, config: config, warnings: [.unreadable(file: "ideogram4.json")])
    let text = state(data: data).status
    #expect(text.contains("ideogram4.json") && text.contains("no_such_category"))
  }

  @Test func theSendButtonNeedsThePluginToBeOnAndFree() {
    let state = state()
    #expect(state.canSend)
    state.isSending = true
    #expect(!state.canSend)
    state.isSending = false
    state.editJSON("  \n ")  // a text emptied by hand
    #expect(!state.canSend)
    state.restoreJSON()
    state.active = false
    #expect(!state.canSend)
  }
}

@MainActor
@Suite("Sending the caption")
struct SenderTests {
  @Test func theCaptionGoesInThePromptAndTheNegativePromptIsEmptied() async {
    var sent: [String: Any]?
    let sender = I4Sender(contribute: { body in sent = body; return ["type": "contribute"] }, italian: true)
    let outcome = await sender.send("{ }")
    let fields = sent?["fields"] as? [String: Any]
    #expect(fields?["prompt"] as? String == "{ }" && fields?["negativePrompt"] as? String == "")
    #expect(fields?.count == 2 && sent?.count == 1)
    #expect(outcome == I4Sender.Outcome(status: L.text(.sent, italian: true), sent: true))
  }

  @Test func conflictsErrorsAndSilenceAreTold() async {
    let conflicted = await I4Sender(contribute: { _ in ["conflicts": 2] }, italian: false).send("x")
    #expect(conflicted.status == "Caption sent. 2 conflict(s) waiting in the app." && conflicted.sent)
    let refused = await I4Sender(contribute: { _ in ["type": "error", "text": "No tab"] }, italian: false).send("x")
    #expect(refused == I4Sender.Outcome(status: "No tab", sent: false))
    let silent = await I4Sender(contribute: { _ in nil }, italian: true).send("x")
    #expect(silent == I4Sender.Outcome(status: L.text(.notAnswered, italian: true), sent: false))
  }
}

@Suite("The words of the plug-in")
struct StringsTests {
  @Test func bothLanguagesHaveEveryKeyWithTheSamePlaceholders() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: false) && L.isDefined(key, italian: true), "\(key)")
      func placeholders(_ text: String) -> [String] { text.matches(of: /%[@d]/).map { String($0.output) } }
      #expect(placeholders(L.text(key, italian: true)) == placeholders(L.text(key, italian: false)), "\(key)")
    }
  }
}
