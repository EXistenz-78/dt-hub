import DTHubPluginKit
import Foundation
import SwiftUI

/// What the tab shows and edits.
@MainActor
final class PMState: ObservableObject {
  let data: PMData
  private let store: PMStore
  private let customStore: CustomTermsStore
  private let shuffler: (PromptDatabase, Set<String>, StyleMode) -> [String]
  let italian: Bool

  @Published var description: String { didSet { persist() } }
  @Published var selection: Set<String> { didSet { persist() } }
  @Published var mode: StyleMode { didSet { persist() } }
  @Published var booru: Bool { didSet { persist() } }
  @Published var openGroups: Set<String> { didSet { persist() } }
  @Published var openCategories: Set<String> { didSet { persist() } }
  @Published var query = "" { didSet { rebuildVisible() } }
  @Published private(set) var customTerms: [CustomTerm]
  @Published private(set) var visibleTree: TermTree
  @Published var status = ""
  @Published var isWriting = false
  @Published var isMakingScene = false
  @Published var active = false
  /// The category where the user is typing a new term, and what they typed.
  @Published var addingIn: String?
  @Published var newTermText = ""

  private(set) var family: String?
  private(set) var startImage: String?
  private(set) var moodboard: [String] = []
  private(set) var languageModels: [DTHubLanguageModel] = []
  private var fullTree: TermTree

  init(
    data: PMData = PMData.load(), store: PMStore = PMStore(), customStore: CustomTermsStore = CustomTermsStore(),
    italian: Bool = L.systemIsItalian,
    shuffler: @escaping (PromptDatabase, Set<String>, StyleMode) -> [String] = { database, hidden, mode in
      var generator = SystemRandomNumberGenerator()
      return Shuffler.pick(database: database, hidden: hidden, mode: mode, using: &generator)
    }
  ) {
    self.data = data
    self.store = store
    self.customStore = customStore
    self.italian = italian
    self.shuffler = shuffler
    let session = store.load()
    description = session.description
    selection = Set(session.selection)
    mode = session.mode
    booru = session.booru
    openGroups = Set(session.openGroups)
    openCategories = Set(session.openCategories)
    let custom = customStore.load()
    customTerms = custom
    let tree = TermTree(database: data.database, custom: custom, hidden: [], italian: italian)
    fullTree = tree
    visibleTree = tree
    status = data.warnings.map { Self.text(for: $0, italian: italian) }.joined(separator: " ")
    rebuild()
  }

  private static func text(for warning: DataWarning, italian: Bool) -> String {
    switch warning {
    case .unreadable(let file): return L.format(.unreadableFile, file, italian: italian)
    case .unknownSchema(let file): return L.format(.unknownSchema, file, italian: italian)
    case .repeatedIDs(let file): return L.format(.repeatedIDs, file, italian: italian)
    }
  }

  // MARK: What the app says

  /// The `context` message: the family decides which categories are hidden and which master prompt is used.
  func update(family: String?, startImage: String?, moodboard: [String], languageModels: [DTHubLanguageModel]) {
    let changed = family != self.family
    self.family = family
    self.startImage = startImage
    self.moodboard = moodboard
    self.languageModels = languageModels
    if changed { rebuild() }
  }

  var master: FamilyPrompt? { family.flatMap { data.masters.families[$0] } }
  var hasBooruSwitch: Bool { family.map(PMFamilies.withBooruSwitch.contains) ?? false }
  var hiddenCategories: Set<String> { Set(master?.hiddenCategories ?? []) }

  // MARK: The list

  private func rebuild() {
    fullTree = TermTree(database: data.database, custom: customTerms, hidden: hiddenCategories, italian: italian)
    rebuildVisible()
  }

  private func rebuildVisible() {
    visibleTree = fullTree.filtered(by: query, database: data.database, italian: italian)
  }

  var selectedTerms: [SelectedTerm] { fullTree.selectedTerms(selection) }

  func chosenCount(inGroup id: String) -> Int { fullTree.chosenCount(inGroup: id, selection: selection) }
  func chosenCount(inCategory id: String) -> Int { fullTree.chosenCount(inCategory: id, selection: selection) }

  func isOpen(group id: String) -> Bool { visibleTree.isFiltered || openGroups.contains(id) }
  func isOpen(category id: String) -> Bool { visibleTree.isFiltered || openCategories.contains(id) }

  func toggleOpen(group id: String) { if !openGroups.insert(id).inserted { openGroups.remove(id) } }
  func toggleOpen(category id: String) { if !openCategories.insert(id).inserted { openCategories.remove(id) } }

  func setChosen(_ id: String, _ chosen: Bool) {
    if chosen { selection.insert(id) } else { selection.remove(id) }
  }

  func clearAll() { selection = [] }

  /// A new random selection (it replaces the old one), from the categories the family keeps.
  func shuffle() { selection = Set(shuffler(data.database, hiddenCategories, mode)) }

  // MARK: The user's own terms

  /// Adds the term the user typed to `categoryID` and chooses it.
  func addCustomTerm() {
    guard let category = addingIn else { return }
    do {
      let term = try customStore.add(text: newTermText, to: category)
      customTerms = customStore.load()
      rebuild()
      selection.insert(term.id)
      openCategories.insert(category)
      addingIn = nil
      newTermText = ""
    } catch CustomTermsStore.Failure.empty {
      addingIn = nil
      newTermText = ""
    } catch {
      status = L.text(.customNotSaved, italian: italian)
    }
  }

  func removeCustomTerm(_ id: String) {
    do {
      try customStore.remove(id: id)
      customTerms = customStore.load()
      selection.remove(id)
      rebuild()
    } catch {
      status = L.text(.customNotSaved, italian: italian)
    }
  }

  // MARK: The button

  /// There is something to write from, a master prompt to write with, and the plug-in is on and not busy.
  var canWrite: Bool {
    active && !isWriting && !isMakingScene && master != nil
      && (!description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedTerms.isEmpty)
  }

  var writeRequest: PMWriter.Request? {
    guard let family else { return nil }
    return PMWriter.Request(
      family: family, masters: data.masters, description: description, terms: selectedTerms,
      booru: booru && hasBooruSwitch, startImage: startImage, moodboard: moodboard, languageModels: languageModels)
  }

  private func persist() {
    store.save(
      PMSession(
        description: description, selection: selection.sorted(), mode: mode, booru: booru,
        openGroups: openGroups.sorted(), openCategories: openCategories.sorted()))
  }
}
