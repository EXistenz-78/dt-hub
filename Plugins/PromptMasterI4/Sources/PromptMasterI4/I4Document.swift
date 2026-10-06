import Foundation

/// One element of the caption: an object or a piece of lettering, with a box (or none).
struct I4Element: Codable, Equatable, Identifiable, Sendable {
  var id: Int
  var type: ElementType = .obj
  var desc = ""
  /// The term chosen in the Text & Lettering menu (a text element only).
  var lettering: String?
  /// The words the lettering says, rendered as they are.
  var text = ""
  var bbox: BBox?
  var colors: [String] = []

  /// What the caption gets for `desc` until a language model rewrites it: the description and the lettering term.
  func rawDescription(catalog: I4Catalog) -> String {
    let term = type == .text ? lettering.flatMap { id in catalog.lettering.first { $0.id == id }?.en } : nil
    return I4Document.join([desc, term ?? ""])
  }
}

/// Everything the user chose and wrote (spec §4, §5). The terms are a set of ids: each belongs to one category, and the
/// rules of the lists (one per category, one medium) are kept by `choose`.
struct I4Document: Codable, Equatable, Sendable {
  var description = ""
  var mode: StyleMode = .photo
  var selection: Set<String> = []
  var colors: [String] = []
  var background = ""
  var elements: [I4Element] = []
  var nextElementID = 1

  static func join(_ parts: [String]) -> String {
    parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ")
  }

  // MARK: The lists

  /// Chooses `termID`, or unchooses it if it is chosen. One term per category; Medium and Background take one term in all
  /// their categories. A term the current mode does not show is ignored.
  mutating func choose(_ termID: String, catalog: I4Catalog) {
    guard let category = catalog.category(ofTerm: termID), let field = catalog.field(ofCategory: category.id),
      I4Field.listed.contains(field) || field == .background
    else { return }
    let visible = catalog.categories(for: field, mode: mode)
    guard visible.contains(where: { $0.id == category.id }) else { return }
    if selection.contains(termID) {
      selection.remove(termID)
      return
    }
    let sameChoice = (field == .medium || field == .background) ? visible : [category]
    for other in sameChoice { selection.subtract(other.terms.map(\.id)) }
    selection.insert(termID)
  }

  /// Photo ↔ Art: the lists change, and the choices of the categories that disappear go with them.
  mutating func setMode(_ newMode: StyleMode, catalog: I4Catalog) {
    mode = newMode
    var shown = Set<String>()
    for field in I4Field.listed + [.background] {
      for category in catalog.categories(for: field, mode: newMode) { shown.formUnion(category.terms.map(\.id)) }
    }
    selection.formIntersection(shown)
  }

  /// The chosen term of `category`, if any.
  func chosen(in category: PMCategory) -> PMTerm? { category.terms.first { selection.contains($0.id) } }

  /// The chosen terms of a field, in the order of its categories.
  func terms(in field: I4Field, catalog: I4Catalog) -> [PMTerm] {
    catalog.categories(for: field, mode: mode).compactMap { chosen(in: $0) }
  }

  func chosenCount(in field: I4Field, catalog: I4Catalog) -> Int { terms(in: field, catalog: catalog).count }

  /// The English names of the chosen terms of a field, joined (what the caption holds until the language model writes).
  func rawText(_ field: I4Field, catalog: I4Catalog) -> String {
    Self.join(terms(in: field, catalog: catalog).map(\.en))
  }

  /// The user's words, then the chosen backdrop.
  func rawBackground(catalog: I4Catalog) -> String {
    Self.join([background, rawText(.background, catalog: catalog)])
  }

  // MARK: The palette

  var canAddColor: Bool { colors.count < Palette.styleLimit }

  mutating func addColor(_ hex: String) {
    guard canAddColor, let value = Palette.normalize(hex) else { return }
    colors.append(value)
  }

  // MARK: The elements

  @discardableResult
  mutating func addElement(type: ElementType = .obj, bbox: BBox? = nil) -> Int {
    let id = nextElementID
    nextElementID += 1
    elements.append(I4Element(id: id, type: type, bbox: bbox))
    return id
  }

  mutating func removeElement(_ id: Int) { elements.removeAll { $0.id == id } }

  /// Moves an element one place up (-1) or down (+1) in the list: the order is the stacking order of the caption.
  mutating func moveElement(_ id: Int, by step: Int) {
    guard let index = elements.firstIndex(where: { $0.id == id }), elements.indices.contains(index + step) else { return }
    elements.swapAt(index, index + step)
  }

  mutating func updateElement(_ id: Int, _ change: (inout I4Element) -> Void) {
    guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
    change(&elements[index])
  }

  mutating func addElementColor(_ id: Int, _ hex: String) {
    guard let value = Palette.normalize(hex) else { return }
    updateElement(id) { if $0.colors.count < Palette.elementLimit { $0.colors.append(value) } }
  }

  // MARK: The caption

  /// The caption with the raw texts: the user's words and the English names of the chosen terms.
  func caption(catalog: I4Catalog) -> I4Caption {
    I4Caption(
      description: description.trimmingCharacters(in: .whitespacesAndNewlines),
      aesthetics: rawText(.aesthetics, catalog: catalog), lighting: rawText(.lighting, catalog: catalog),
      style: rawText(.style, catalog: catalog), medium: rawText(.medium, catalog: catalog), mode: mode, colors: colors,
      background: rawBackground(catalog: catalog),
      elements: elements.map {
        I4Caption.Element(
          type: $0.type, bbox: $0.bbox, text: $0.text, desc: $0.rawDescription(catalog: catalog), colors: $0.colors)
      })
  }
}
