import Foundation
import Testing

@testable import PromptMaster

@MainActor
@Suite("The state of the tab")
struct PMStateTests {
  private func defaults() -> UserDefaults { UserDefaults(suiteName: "pm-state-\(UUID().uuidString)")! }
  private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("pm-state-\(UUID().uuidString)") }

  private func state(
    defaults: UserDefaults? = nil, custom: URL? = nil, shuffled: [String] = ["fr_closeup", "lq_soft_diffused"]
  ) -> PMState {
    let state = PMState(
      store: PMStore(defaults: defaults ?? self.defaults()), customStore: CustomTermsStore(folder: custom ?? folder()),
      italian: true, shuffler: { _, _, _ in shuffled })
    state.update(family: "flux2_9b", languageModels: [])
    state.active = true
    return state
  }

  @Test func choosingATermAddsItToTheListOfChosenTermsInTheOrderOfTheList() {
    let state = state()
    state.setChosen("fr_closeup", true)
    state.setChosen("fr_extreme_closeup", true)
    #expect(state.selectedTerms.map(\.id) == ["fr_extreme_closeup", "fr_closeup"])
    #expect(state.chosenCount(inCategory: "framing") == 2 && state.chosenCount(inGroup: "A") == 2)
    state.setChosen("fr_closeup", false)
    #expect(state.selectedTerms.map(\.id) == ["fr_extreme_closeup"])
  }

  @Test func clearingTheListEmptiesTheSelection() {
    let state = state()
    state.setChosen("fr_closeup", true)
    state.clearAll()
    #expect(state.selection.isEmpty && state.selectedTerms.isEmpty)
  }

  @Test func theShuffleReplacesTheSelectionWithWhatTheShufflerPicksForTheFamilyAndMode() {
    var seen: (Set<String>, StyleMode)?
    let state = PMState(
      store: PMStore(defaults: defaults()), customStore: CustomTermsStore(folder: folder()), italian: true,
      shuffler: { _, hidden, mode in seen = (hidden, mode); return ["lq_soft_diffused"] })
    state.update(family: "z_image", languageModels: [])
    state.setChosen("fr_closeup", true)
    state.mode = .art
    state.shuffle()
    #expect(state.selection == ["lq_soft_diffused"])
    #expect(seen?.1 == .art && seen?.0.contains("typography_text") == true)  // z_image hides it
  }

  @Test func theFamilyHidesCategoriesAndTheSelectionOfAHiddenOneIsNotSent() {
    let state = state()
    #expect(state.visibleTree.groups.flatMap(\.categories).contains { $0.id == "typography_text" })
    let typography = PMData.embeddedDatabase.categories.first { $0.id == "typography_text" }!.terms[0].id
    state.setChosen(typography, true)
    #expect(state.selectedTerms.map(\.id) == [typography])
    state.update(family: "z_image", languageModels: [])
    #expect(!state.visibleTree.groups.flatMap(\.categories).contains { $0.id == "typography_text" })
    #expect(state.selectedTerms.isEmpty && state.selection == [typography])  // kept for when the family changes back
  }

  @Test func theSearchNarrowsTheListAndOpensIt() {
    let state = state()
    #expect(!state.isOpen(group: "A"))
    state.query = "primissimo"
    #expect(state.visibleTree.isFiltered && state.isOpen(group: "A") && state.isOpen(category: "framing"))
    #expect(state.visibleTree.groups.flatMap(\.categories).flatMap(\.terms).contains { $0.id == "fr_extreme_closeup" })
    state.query = ""
    #expect(!state.isOpen(group: "A"))
  }

  @Test func groupsAndCategoriesOpenAndClose() {
    let state = state()
    state.toggleOpen(group: "A")
    state.toggleOpen(category: "framing")
    #expect(state.isOpen(group: "A") && state.isOpen(category: "framing"))
    state.toggleOpen(group: "A")
    #expect(!state.isOpen(group: "A"))
  }

  // MARK: Custom terms

  @Test func aTermTheUserTypesJoinsItsCategoryAndIsChosen() {
    let state = state()
    state.addingIn = "framing"
    state.newTermText = " dal basso a sinistra "
    state.addCustomTerm()
    let term = state.customTerms[0]
    #expect(term.text == "dal basso a sinistra" && state.selection.contains(term.id) && state.addingIn == nil)
    #expect(state.visibleTree.groups[0].categories[0].terms.last?.id == term.id)
    #expect(state.isOpen(category: "framing"))
    state.removeCustomTerm(term.id)
    #expect(state.customTerms.isEmpty && !state.selection.contains(term.id))
  }

  @Test func anEmptyNewTermJustClosesTheField() {
    let state = state()
    state.addingIn = "framing"
    state.newTermText = "   "
    state.addCustomTerm()
    #expect(state.customTerms.isEmpty && state.addingIn == nil && state.status.isEmpty)
  }

  @Test func ifTheFileCannotBeWrittenTheStatusSaysSo() throws {
    let custom = folder()
    try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: custom.appendingPathComponent("custom-terms.json"))
    let state = state(custom: custom)
    state.addingIn = "framing"
    state.newTermText = "x"
    state.addCustomTerm()
    #expect(state.status == "Non si è potuto salvare il tuo termine." && state.customTerms.isEmpty)
  }

  // MARK: The button

  @Test func theButtonNeedsTheTabOnATextOrATermAndAMasterPrompt() {
    let state = state()
    #expect(!state.canWrite)  // nothing yet
    state.description = "  \n "
    #expect(!state.canWrite)
    state.description = "un porto"
    #expect(state.canWrite)
    state.description = ""
    state.setChosen("fr_closeup", true)
    #expect(state.canWrite)
    state.active = false
    #expect(!state.canWrite)
    state.active = true
    state.isWriting = true
    #expect(!state.canWrite)
    state.isWriting = false
    state.update(family: "ideogram_4", languageModels: [])
    #expect(!state.canWrite && state.writeRequest?.family == "ideogram_4")
  }

  @Test func theButtonIsOffWhileASceneIsBeingWritten() {
    let state = state()
    state.description = "un porto"
    #expect(state.canWrite)
    state.isMakingScene = true
    #expect(!state.canWrite)  // the scene would replace the text the request was made from
    state.isMakingScene = false
    #expect(state.canWrite)
  }

  @Test func theRequestCarriesWhatTheTabKnowsAndTheBooruSwitchOnlyWhereItExists() throws {
    let state = state()
    state.description = "ciao"
    state.booru = true
    state.update(family: "v1", languageModels: [])
    var request = try #require(state.writeRequest)
    #expect(request.booru && request.description == "ciao")
    state.update(family: "flux1", languageModels: [])
    request = try #require(state.writeRequest)
    #expect(!request.booru)
  }

  // MARK: Memory

  @Test func theSessionComesBackInANewState() {
    let shared = defaults()
    let custom = folder()
    let first = state(defaults: shared, custom: custom)
    first.description = "un porto all'alba"
    first.setChosen("fr_closeup", true)
    first.mode = .art
    first.booru = true
    first.toggleOpen(group: "B")
    first.toggleOpen(category: "light_source")
    let second = state(defaults: shared, custom: custom)
    #expect(second.description == "un porto all'alba" && second.selection == ["fr_closeup"])
    #expect(second.mode == .art && second.booru && second.openGroups == ["B"] && second.openCategories == ["light_source"])
    #expect(second.query.isEmpty)
  }

  @Test func aSessionThatCannotBeReadStartsEmpty() {
    let shared = defaults()
    shared.set(Data("garbage".utf8), forKey: PMStore.key)
    #expect(state(defaults: shared).selection.isEmpty)
  }

  @Test func aFileThatCouldNotBeReadAtStartIsMentionedInTheStatus() throws {
    let root = folder()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: root.appendingPathComponent("prompt-database.json"))
    let data = PMData.load(folder: root)
    let state = PMState(
      data: data, store: PMStore(defaults: defaults()), customStore: CustomTermsStore(folder: folder()), italian: false)
    #expect(state.status == "prompt-database.json cannot be read: using the copy built into the plug-in.")
  }
}
