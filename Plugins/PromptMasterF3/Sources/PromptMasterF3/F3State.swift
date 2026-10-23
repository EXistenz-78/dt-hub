import DTHubPluginKit
import Foundation
import SwiftUI

/// Quello che il tab mostra e modifica.
@MainActor
final class F3State: ObservableObject {
  let data: F3Data
  let catalog: F3Catalog
  private var store: F3Store
  /// Dove stava la sessione prima dei progetti: quello che adotta il primo progetto.
  private let legacyStorage: any F3Storage
  private let shuffler: (F3Catalog, StyleMode) -> Set<String>
  /// L'attesa prima di sincronizzare gli id (iniettabile nei test).
  private let sleep: @Sendable (Duration) async -> Void
  let italian: Bool
  static let debounce = Duration.milliseconds(800)

  @Published var document: F3Document { didSet { persist() } }
  @Published var openGroups: Set<String> { didSet { persist() } }
  @Published var openCategories: Set<String> { didSet { persist() } }
  @Published var status = ""
  @Published var isSending = false
  /// «Scrivi con LLM» è in corso.
  @Published var isWriting = false
  @Published var active = false
  /// L'elemento selezionato sul canvas o nell'elenco (stato della vista: non si ricorda).
  @Published var selectedElement: String?
  /// La dimensione della Generazione, come l'app l'ha detta per ultima: il canvas ne prende le proporzioni.
  @Published private(set) var generationSize: CGSize?
  /// Gli elementi e gli id tolti dal testo (ricordati per la sessione) e il testo con cui sono allineati.
  private var sync = F3Sync()
  private var syncedComposition: String
  /// La sincronizzazione in attesa (ritardata); i test la aspettano.
  private(set) var pendingSync: Task<Void, Never>?
  /// Dove si leggono il master prompt e quello dell'utente (a ogni scrittura).
  let promptFolder: DTHubPromptFolder
  /// La cartella del progetto aperto (dove stanno `state.json` e `llm/`); nil finché l'app non ha detto il progetto.
  private(set) var projectFolder: URL?

  init(
    data: F3Data = F3Data.load(), promptFolder: DTHubPromptFolder = F3Prompts.folder(), store: F3Store = F3Store(),
    italian: Bool = L.systemIsItalian,
    shuffler: @escaping (F3Catalog, StyleMode) -> Set<String> = { catalog, mode in
      var generator = SystemRandomNumberGenerator()
      return F3Shuffler.pick(catalog: catalog, mode: mode, using: &generator)
    },
    sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
  ) {
    self.data = data
    self.promptFolder = promptFolder
    self.store = store
    legacyStorage = store.storage
    self.italian = italian
    self.shuffler = shuffler
    self.sleep = sleep
    let catalog = F3Catalog(database: data.database, config: data.config)
    self.catalog = catalog
    let session = store.load()
    var document = session.document
    document.setMode(document.mode, catalog: catalog)
    self.document = document
    openGroups = Set(session.openGroups)
    openCategories = Set(session.openCategories)
    syncedComposition = document.composition
    sync = Self.makeSync(for: document)
    status = (data.warnings.map { Self.text(for: $0, italian: italian) } + F3Prompts.problems(in: promptFolder)).joined(separator: " ")
  }

  private static func makeSync(for document: F3Document) -> F3Sync {
    var sync = F3Sync()
    sync.elements = document.elements
    sync.nextColor = (document.elements.map(\.colorIndex).max() ?? -1) + 1
    return sync
  }

  private static func text(for warning: DataWarning, italian: Bool) -> String {
    switch warning {
    case .unreadable(let file): return "\(file): unreadable"
    case .unknownSchema(let file): return "\(file): unknown layout"
    case .repeatedIDs(let file): return "\(file): repeated ids"
    }
  }

  // MARK: Cosa dice l'app

  func update(generationSize: CGSize?) { self.generationSize = generationSize }

  /// Larghezza su altezza della Generazione; un quadrato finché l'app non l'ha detta.
  var canvasAspect: Double {
    guard let size = generationSize, size.width > 0, size.height > 0 else { return 1 }
    return Double(size.width / size.height)
  }

  // MARK: Gli elenchi

  func isChosen(_ termID: String) -> Bool { document.selection.contains(termID) }
  func choose(_ termID: String) { document.choose(termID, catalog: catalog) }
  func setMode(_ mode: StyleMode) { document.setMode(mode, catalog: catalog) }
  func shuffle() { document.selection = shuffler(catalog, document.mode) }
  func isOpen(group id: String) -> Bool { openGroups.contains(id) }
  func isOpen(category id: String) -> Bool { openCategories.contains(id) }
  func toggleOpen(group id: String) { if !openGroups.insert(id).inserted { openGroups.remove(id) } }
  func toggleOpen(category id: String) { if !openCategories.insert(id).inserted { openCategories.remove(id) } }

  // MARK: La composizione e gli elementi

  /// Il testo cambiato: si sincronizza quando si smette di scrivere (~0,8 s), o subito con `commitComposition()`.
  func compositionChanged(_ text: String) {
    document.composition = text
    pendingSync?.cancel()
    pendingSync = Task { [weak self, sleep] in
      await sleep(Self.debounce)
      guard !Task.isCancelled else { return }
      self?.commitComposition()
    }
  }

  /// Allinea elementi e box agli id del testo (la perdita del fuoco la chiama subito).
  func commitComposition() {
    pendingSync?.cancel()
    pendingSync = nil
    guard document.composition != syncedComposition else { return }
    sync.elements = document.elements
    let aspect = canvasAspect
    let taken = document.elements.map(\.box)
    var placed: [BBox] = []
    _ = sync.apply(oldText: syncedComposition, newText: document.composition) { index in
      let box = F3DefaultBox.box(index: index, aspect: aspect, taken: taken + placed)
      placed.append(box)
      return box
    }
    syncedComposition = document.composition
    document.elements = sync.elements
    if let selected = selectedElement, document.element(selected) == nil { selectedElement = nil }
  }

  /// Gli id che compaiono più volte nel testo: l'avviso consiglia di numerarli.
  var duplicateIDs: [String] {
    var seen = Set<String>(), result: [String] = []
    for match in F3IDParser.ids(in: document.composition) where !seen.insert(match.id).inserted && !result.contains(match.id) {
      result.append(match.id)
    }
    return result
  }

  var problems: [F3Problem] {
    var list = F3Composer.problems(composition: document.composition, elements: document.elements)
    for id in duplicateIDs { list.append(.duplicateID(id)) }
    return list
  }

  /// Rimuovere una scheda toglie anche i suoi `<id>` dal testo (il testo è la sola fonte degli id).
  func removeElement(_ id: String) {
    var text = document.composition
    for match in F3IDParser.ids(in: text).reversed() where match.id == id { text.removeSubrange(match.range) }
    document.composition = text
    commitComposition()
  }

  func moveElement(_ id: String, by step: Int) { document.moveElement(id, by: step) }

  /// Il binding di un campo di un elemento. Legge dallo stato, non dalla copia dell'elemento con cui la scheda è stata disegnata:
  /// una copia in ritardo ridà all'editor il testo di prima tra due battute e il cursore salta in fondo. `fallback` vale solo se
  /// l'elemento è sparito nel frattempo.
  func elementBinding<T>(_ id: String, _ keyPath: WritableKeyPath<F3Element, T>, fallback: T) -> Binding<T> {
    Binding(
      get: { [unowned self] in document.element(id)?[keyPath: keyPath] ?? fallback },
      set: { [unowned self] value in update(element: id) { $0[keyPath: keyPath] = value } })
  }

  func update(element id: String, _ change: (inout F3Element) -> Void) {
    guard let index = document.elements.firstIndex(where: { $0.id == id }) else { return }
    change(&document.elements[index])
  }

  // MARK: Il canvas

  var canvasItems: [CanvasItem] { document.elements.map { CanvasItem(id: $0.id, colorIndex: $0.colorIndex, box: $0.box) } }

  /// Un gesto finito sul canvas: sposta o ridimensiona, o seleziona; sul vuoto un clic toglie la selezione.
  func canvasEnd(_ drag: CanvasDrag, geometry: CanvasGeometry) {
    switch drag.mode {
    case .none:
      if !drag.moved { selectedElement = nil }
    case .tag(let id):
      if !drag.moved { selectedElement = id }
    case .move(let id, _), .resize(let id, _, _):
      selectedElement = id
      if drag.moved, let box = geometry.result(of: drag) { update(element: id) { $0.box = box } }
    }
  }

  // MARK: Invia e scrivi

  var terms: [String] { catalog.termNames(document.selection, mode: document.mode) }

  /// Il testo che «Invia» manda.
  var sendText: String {
    F3Composer.text(description: document.description, terms: terms, composition: document.composition, elements: document.elements)
  }

  /// Il plug-in è attivo, non si sta inviando né scrivendo, il testo è allineato e non ci sono problemi.
  var canSend: Bool {
    active && !isSending && !isWriting && problems.isEmpty && syncedComposition == document.composition
  }

  var hasWritableContent: Bool {
    !document.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !document.selection.isEmpty
      || !document.composition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || document.elements.contains { !$0.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  var canWrite: Bool { active && !isWriting && !isSending && hasWritableContent }
  var canUndo: Bool { document.snapshot != nil && !isWriting }

  var writeSystem: String { F3Prompts.system(in: promptFolder) }
  var writeOptions: DTHubLLMOptions {
    let settings = data.config.options
    return DTHubLLMOptions(
      temperature: settings.temperature, maxTokens: settings.maxTokens, thinking: settings.thinking, timeout: settings.timeout)
  }

  /// Mette nei campi i testi riscritti. Un testo che l'utente ha cambiato mentre l'LLM scriveva resta com'è. Prima si
  /// fotografa lo stato (solo l'ultima fotografia), per «Annulla».
  func apply(_ result: F3WriteResult) {
    var applicable: [F3Rewrite] = []
    var kept: [String] = []
    for rewrite in result.rewrites {
      if currentText(of: rewrite.kind) == rewrite.original { applicable.append(rewrite) } else { kept.append(rewrite.kind.title) }
    }
    var lines = [result.status]
    if !applicable.isEmpty {
      document.snapshot = F3Snapshot.take(from: document)
      for rewrite in applicable {
        switch rewrite.kind {
        case .description:
          document.description = rewrite.text
          document.selection = []
        case .composition: document.composition = rewrite.text
        case .element(let id): update(element: id) { $0.desc = rewrite.text }
        }
      }
      commitComposition()
    }
    if !kept.isEmpty { lines.append(L.format(.changedMeanwhile, kept.joined(separator: ", "), italian: italian)) }
    status = lines.filter { !$0.isEmpty }.joined(separator: " ")
  }

  private func currentText(of kind: F3Part.Kind) -> String? {
    switch kind {
    case .description: return document.description.trimmingCharacters(in: .whitespacesAndNewlines)
    case .composition: return document.composition.trimmingCharacters(in: .whitespacesAndNewlines)
    case .element(let id): return document.element(id)?.desc.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  /// «Annulla»: rimette i testi di prima (solo l'ultima scrittura) e riallinea gli elementi agli id del testo.
  func undo() {
    guard let snapshot = document.snapshot else { return }
    pendingSync?.cancel()
    var restored = document
    snapshot.restore(into: &restored)
    document = restored
    commitComposition()
    // Gli elementi ricomparsi dagli id tornano con i testi della fotografia.
    for index in document.elements.indices {
      if let desc = snapshot.descs[document.elements[index].id] { document.elements[index].desc = desc }
    }
    status = L.text(.undone, italian: italian)
  }

  // MARK: Progetti

  /// Vero mentre la sessione di un progetto viene letta nel tab: i cambi che ne vengono non si riscrivono.
  private var isRestoring = false

  /// L'app ha aperto un progetto: il tab mostra la sessione di quel progetto (`adoptLegacy`: il primo progetto di sempre prende la
  /// sessione che il tab aveva prima).
  func switchProject(folder: URL, adoptLegacy: Bool) {
    pendingSync?.cancel()
    projectFolder = folder
    store.storage = FileStorage(folder: folder)
    if adoptLegacy { store.adoptLegacy(from: legacyStorage) }
    let session = store.load()
    var document = session.document
    document.setMode(document.mode, catalog: catalog)
    isRestoring = true
    self.document = document
    openGroups = Set(session.openGroups)
    openCategories = Set(session.openCategories)
    selectedElement = nil
    syncedComposition = document.composition
    sync = Self.makeSync(for: document)
    isRestoring = false
  }

  private func persist() {
    guard !isRestoring else { return }
    store.save(
      F3Session(document: document, openGroups: openGroups.sorted(), openCategories: openCategories.sorted()))
  }
}
