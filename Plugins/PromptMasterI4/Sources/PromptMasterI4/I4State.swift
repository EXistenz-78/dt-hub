import Foundation
import SwiftUI

/// What the tab shows and edits.
@MainActor
final class I4State: ObservableObject {
  let data: I4Data
  let catalog: I4Catalog
  private let store: I4Store
  private let shuffler: (I4Catalog, StyleMode) -> Set<String>
  private let colorMaker: () -> String
  let italian: Bool

  @Published var document: I4Document { didSet { persist() } }
  /// The JSON edited by hand: while it is set, it is what «Send» sends.
  @Published private(set) var editedJSON: String? { didSet { persist() } }
  @Published var openSections: Set<String> { didSet { persist() } }
  @Published var openCategories: Set<String> { didSet { persist() } }
  @Published var expandedElements: Set<Int> { didSet { persist() } }
  @Published var status = ""
  @Published var isSending = false
  @Published var active = false

  init(
    data: I4Data = I4Data.load(), store: I4Store = I4Store(), italian: Bool = L.systemIsItalian,
    shuffler: @escaping (I4Catalog, StyleMode) -> Set<String> = { catalog, mode in
      var generator = SystemRandomNumberGenerator()
      return I4Shuffler.pick(catalog: catalog, mode: mode, using: &generator)
    },
    colorMaker: @escaping () -> String = {
      var generator = SystemRandomNumberGenerator()
      return Palette.random(using: &generator)
    }
  ) {
    self.data = data
    self.store = store
    self.italian = italian
    self.shuffler = shuffler
    self.colorMaker = colorMaker
    let catalog = I4Catalog(database: data.database, config: data.config)
    self.catalog = catalog
    let session = store.load()
    var document = session.document
    // A choice that is no longer in the vocabulary or not shown in the mode would only confuse the lists.
    document.setMode(document.mode, catalog: catalog)
    self.document = document
    editedJSON = session.editedJSON
    openSections = Set(session.openSections)
    openCategories = Set(session.openCategories)
    expandedElements = Set(session.expandedElements)
    let notes =
      data.warnings.map { Self.text(for: $0, italian: italian) }
      + catalog.missingCategories.map { L.format(.missingCategory, $0, italian: italian) }
    status = notes.joined(separator: " ")
  }

  private static func text(for warning: DataWarning, italian: Bool) -> String {
    switch warning {
    case .unreadable(let file): return L.format(.unreadableFile, file, italian: italian)
    case .unknownSchema(let file): return L.format(.unknownSchema, file, italian: italian)
    case .repeatedIDs(let file): return L.format(.repeatedIDs, file, italian: italian)
    }
  }

  // MARK: The lists

  func isChosen(_ termID: String) -> Bool { document.selection.contains(termID) }
  func choose(_ termID: String) { document.choose(termID, catalog: catalog) }
  func setMode(_ mode: StyleMode) { document.setMode(mode, catalog: catalog) }
  func shuffle() { document.selection = shuffler(catalog, document.mode) }

  func isOpen(section id: String) -> Bool { openSections.contains(id) }
  func isOpen(category id: String) -> Bool { openCategories.contains(id) }
  func toggleOpen(section id: String) { if !openSections.insert(id).inserted { openSections.remove(id) } }
  func toggleOpen(category id: String) { if !openCategories.insert(id).inserted { openCategories.remove(id) } }

  // MARK: The palette

  func addColor() { document.addColor(colorMaker()) }
  func addColor(toElement id: Int) { document.addElementColor(id, colorMaker()) }

  // MARK: The elements

  func addElement() {
    let id = document.addElement()
    expandedElements.insert(id)
  }

  func removeElement(_ id: Int) {
    document.removeElement(id)
    expandedElements.remove(id)
  }

  func toggleExpanded(_ id: Int) { if !expandedElements.insert(id).inserted { expandedElements.remove(id) } }

  // MARK: The JSON

  /// The caption made from the fields.
  var generatedJSON: String { document.caption(catalog: catalog).json }
  var hasEditedJSON: Bool { editedJSON != nil }
  /// What «Send» sends and the review window shows.
  var jsonText: String { editedJSON ?? generatedJSON }

  /// The review window changed the text: a text equal to the caption of the fields is no edit at all.
  func editJSON(_ text: String) { editedJSON = text == generatedJSON ? nil : text }
  func restoreJSON() { editedJSON = nil }

  /// The plug-in is on, nothing is being sent and there is something to send (a text emptied by hand sends nothing).
  var canSend: Bool { active && !isSending && !jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  private func persist() {
    store.save(
      I4Session(
        document: document, editedJSON: editedJSON, openSections: openSections.sorted(),
        openCategories: openCategories.sorted(), expandedElements: expandedElements.sorted()))
  }
}
