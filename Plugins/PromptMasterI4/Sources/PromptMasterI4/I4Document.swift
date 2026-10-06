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
  /// The sentences a language model wrote, by field (`I4FieldInfo.id`), each with the input it was written for.
  var written: [String: WrittenPhrase] = [:]

  init() {}

  /// A session saved before the language model existed has no `written`: it reads as empty.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    description = try container.decode(String.self, forKey: .description)
    mode = try container.decode(StyleMode.self, forKey: .mode)
    selection = try container.decode(Set<String>.self, forKey: .selection)
    colors = try container.decode([String].self, forKey: .colors)
    background = try container.decode(String.self, forKey: .background)
    elements = try container.decode([I4Element].self, forKey: .elements)
    nextElementID = try container.decode(Int.self, forKey: .nextElementID)
    written = try container.decodeIfPresent([String: WrittenPhrase].self, forKey: .written) ?? [:]
  }

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

  /// Changes or removes the color at `index`; an index that is not there any more (the view may act on a swatch that has
  /// just gone) does nothing.
  mutating func setColor(at index: Int, to hex: String) {
    guard colors.indices.contains(index), let value = Palette.normalize(hex) else { return }
    colors[index] = value
  }

  mutating func removeColor(at index: Int) {
    guard colors.indices.contains(index) else { return }
    colors.remove(at: index)
  }

  // MARK: The elements

  @discardableResult
  mutating func addElement(type: ElementType = .obj, bbox: BBox? = nil) -> Int {
    let id = nextElementID
    nextElementID += 1
    elements.append(I4Element(id: id, type: type, bbox: bbox))
    return id
  }

  /// Object ↔ text: the description, the lettering term and the printed text are all kept.
  mutating func toggleType(_ id: Int) {
    updateElement(id) { $0.type = $0.type == .obj ? .text : .obj }
  }

  mutating func removeElement(_ id: Int) { elements.removeAll { $0.id == id } }

  /// Every element goes; the ids already given are never given again.
  mutating func clearElements() { elements.removeAll() }

  /// The General card goes empty: the description, the chosen terms, the palette and the background. The mode stays.
  mutating func clearGeneral() {
    description = ""
    selection = []
    colors = []
    background = ""
  }

  var hasGeneralContent: Bool {
    !description.isEmpty || !selection.isEmpty || !colors.isEmpty || !background.isEmpty
  }

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

  mutating func setElementColor(_ id: Int, at index: Int, to hex: String) {
    guard let value = Palette.normalize(hex) else { return }
    updateElement(id) { if $0.colors.indices.contains(index) { $0.colors[index] = value } }
  }

  mutating func removeElementColor(_ id: Int, at index: Int) {
    updateElement(id) { if $0.colors.indices.contains(index) { $0.colors.remove(at: index) } }
  }

  // MARK: The caption

  /// The caption: for each field the sentence the language model wrote, when the input it was written for is still the
  /// current one, and otherwise the raw text (the user's words and the English names of the chosen terms).
  func caption(catalog: I4Catalog) -> I4Caption {
    let values = Dictionary(uniqueKeysWithValues: fields(catalog: catalog).map { ($0.id, $0.value) })
    return I4Caption(
      description: values[I4FieldInfo.descriptionID] ?? "", aesthetics: values[I4Field.aesthetics.rawValue] ?? "",
      lighting: values[I4Field.lighting.rawValue] ?? "", style: values[I4Field.style.rawValue] ?? "",
      medium: values[I4Field.medium.rawValue] ?? "", mode: mode, colors: colors,
      background: values[I4Field.background.rawValue] ?? "",
      elements: elements.map {
        I4Caption.Element(
          type: $0.type, bbox: $0.bbox, text: $0.text, desc: values[I4FieldInfo.elementID($0.id)] ?? "", colors: $0.colors)
      })
  }
}
