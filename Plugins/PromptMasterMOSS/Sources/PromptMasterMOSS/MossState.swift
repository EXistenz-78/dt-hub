import DTHubPluginKit
import Foundation
import SwiftUI

/// Quello che il tab mostra e modifica.
@MainActor
final class MossState: ObservableObject {
  let data: MossData
  let catalog: MossCatalog
  private var store: MossStore
  /// Dove stava la sessione prima dei progetti: quello che adotta il primo progetto.
  private let legacyStorage: any MossStorage
  private let shuffler: (MossCatalog, StyleMode) -> Set<String>
  let italian: Bool

  @Published var document: MossDocument { didSet { persist() } }
  @Published var openGroups: Set<String> { didSet { persist() } }
  @Published var openCategories: Set<String> { didSet { persist() } }
  @Published var status = ""
  @Published var isSending = false
  /// «Scrivi con LLM» è in corso.
  @Published var isWriting = false
  @Published var active = false
  /// L'elemento selezionato sul canvas o nell'elenco (stato della vista: non si ricorda).
  @Published var selectedItem: Int?
  /// La dimensione della Generazione, come l'app l'ha detta per ultima. Non si salva: arriva a ogni avvio.
  @Published private(set) var generationSize: PixelSize?
  /// Avviso sopra il canvas quando il RAPPORTO della dimensione è cambiato (i box restano nelle stesse frazioni).
  @Published private(set) var sizeNotice: String?
  /// Il JSON modificato a mano in «Rivedi JSON»: se c'è, è quello che parte con «Invia».
  @Published var reviewOverride: String?
  /// Dove si leggono il master prompt e quello dell'utente (a ogni scrittura).
  let promptFolder: DTHubPromptFolder
  /// La cartella del progetto aperto (dove stanno `state.json` e `llm/`); nil finché l'app non ha detto il progetto.
  private(set) var projectFolder: URL?

  init(
    data: MossData = MossData.load(), promptFolder: DTHubPromptFolder = MossPrompts.folder(), store: MossStore = MossStore(),
    italian: Bool = L.systemIsItalian,
    shuffler: @escaping (MossCatalog, StyleMode) -> Set<String> = { catalog, mode in
      var generator = SystemRandomNumberGenerator()
      return MossShuffler.pick(catalog: catalog, mode: mode, using: &generator)
    }
  ) {
    self.data = data
    self.promptFolder = promptFolder
    self.store = store
    legacyStorage = store.storage
    self.italian = italian
    self.shuffler = shuffler
    let catalog = MossCatalog(database: data.database, config: data.config)
    self.catalog = catalog
    let session = store.load()
    var document = session.document
    document.setMode(document.mode, catalog: catalog)
    self.document = document
    openGroups = Set(session.openGroups)
    openCategories = Set(session.openCategories)
    status = (data.warnings.map { Self.text(for: $0) } + MossPrompts.problems(in: promptFolder)).joined(separator: " ")
  }

  private static func text(for warning: DataWarning) -> String {
    switch warning {
    case .unreadable(let file): return "\(file): unreadable"
    case .unknownSchema(let file): return "\(file): unknown layout"
    case .repeatedIDs(let file): return "\(file): repeated ids"
    }
  }

  // MARK: Cosa dice l'app

  /// L'app ha detto la dimensione della Generazione. Stesso rapporto: si ricalcolano le coordinate in silenzio. Rapporto
  /// diverso: i box restano nelle stesse frazioni e compare l'avviso.
  func update(generationSize new: PixelSize?) {
    defer { generationSize = new }
    guard let old = generationSize, let new, old != new, old.width > 0, old.height > 0, new.width > 0, new.height > 0 else { return }
    let oldRatio = Double(old.width) / Double(old.height), newRatio = Double(new.width) / Double(new.height)
    if abs(oldRatio - newRatio) > 0.005 {
      sizeNotice = L.format(.sizeRatioChanged, old.width, old.height, new.width, new.height, italian: italian)
    }
  }

  func dismissSizeNotice() { sizeNotice = nil }

  /// Larghezza su altezza della Generazione; un quadrato finché l'app non l'ha detta.
  var canvasAspect: Double {
    guard let size = generationSize, size.width > 0, size.height > 0 else { return 1 }
    return Double(size.width) / Double(size.height)
  }

  // MARK: Gli elenchi

  func isChosen(_ termID: String) -> Bool { document.selection.contains(termID) }
  func setMode(_ mode: StyleMode) { document.setMode(mode, catalog: catalog) }
  func shuffle() { document.selection = shuffler(catalog, document.mode) }
  func isOpen(group id: String) -> Bool { openGroups.contains(id) }
  func isOpen(category id: String) -> Bool { openCategories.contains(id) }
  func toggleOpen(group id: String) { if !openGroups.insert(id).inserted { openGroups.remove(id) } }
  func toggleOpen(category id: String) { if !openCategories.insert(id).inserted { openCategories.remove(id) } }

  // MARK: Gli elementi

  func addItem(label: MossLabel, box: FracBox) {
    let id = document.nextItemID
    document.nextItemID += 1
    document.items.append(MossItem(id: id, label: label, caption: "", text: "", tags: "", colors: [], box: box, expanded: true))
    selectedItem = id
  }

  func setLabel(_ label: MossLabel, for id: Int) { update(item: id) { $0.label = label } }

  func update(item id: Int, _ change: (inout MossItem) -> Void) {
    guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
    change(&document.items[index])
  }

  func removeItem(_ id: Int) {
    document.items.removeAll { $0.id == id }
    if selectedItem == id { selectedItem = nil }
  }

  func moveItem(_ id: Int, by step: Int) {
    guard let index = document.items.firstIndex(where: { $0.id == id }), document.items.indices.contains(index + step) else { return }
    document.items.swapAt(index, index + step)
  }

  // MARK: Il canvas

  /// Il menu dei tipi aperto dall'etichetta di un riquadro (stato della vista: non si ricorda).
  @Published var typeMenuItem: Int?

  var canvasItems: [CanvasItem] {
    document.items.enumerated().map { CanvasItem(id: $1.id, number: $0 + 1, label: $1.label, box: $1.box) }
  }

  /// Un gesto finito sul canvas: disegna un box nuovo (un oggetto), sposta o ridimensiona, o apre il menu dei tipi sull'etichetta;
  /// sul vuoto un clic toglie la selezione.
  func canvasEnd(_ drag: CanvasDrag, geometry: CanvasGeometry) {
    switch drag.mode {
    case .draw:
      typeMenuItem = nil
      if drag.moved, let box = geometry.result(of: drag) { addItem(label: .object, box: box) } else { selectedItem = nil }
    case .tag(let id):
      if !drag.moved {
        select(id)
        typeMenuItem = id
      }
    case .move(let id, _), .resize(let id, _, _):
      typeMenuItem = nil
      select(id)
      if drag.moved, let box = geometry.result(of: drag) { update(item: id) { $0.box = box } }
    }
  }

  private func select(_ id: Int) {
    selectedItem = id
    update(item: id) { $0.expanded = true }
  }

  /// Un tipo scelto dal menu dell'etichetta.
  func chooseLabel(_ label: MossLabel, for id: Int) {
    setLabel(label, for: id)
    typeMenuItem = nil
  }

  // MARK: Invia

  var problems: [MossProblem] { MossComposer.problems(document, catalog: catalog, size: generationSize) }

  /// Il JSON che «Invia» manda: quello modificato a mano, altrimenti quello dei campi; nil senza una dimensione utilizzabile.
  func currentJSON() -> String? {
    if let reviewOverride { return reviewOverride }
    guard let size = generationSize, size.isUsable else { return nil }
    return MossComposer.json(document, catalog: catalog, size: size)
  }

  var negativeText: String { MossComposer.negative(document, catalog: catalog) }

  /// Il plug-in è attivo, non si sta inviando né scrivendo e non ci sono problemi.
  var canSend: Bool { active && !isSending && !isWriting && problems.isEmpty }

  // MARK: Scrivi con LLM

  var hasWritableContent: Bool {
    !document.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !catalog.captionLines(document.selection).isEmpty
      || document.freeMeta.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      || document.items.contains { !$0.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.tagList.isEmpty }
  }

  var canWrite: Bool { active && !isWriting && !isSending && hasWritableContent }
  var canUndo: Bool { document.snapshot != nil && !isWriting }

  var writeSystem: String { MossPrompts.system(in: promptFolder) }
  var writeOptions: DTHubLLMOptions {
    let settings = data.config.options
    return DTHubLLMOptions(
      temperature: settings.temperature, maxTokens: settings.maxTokens, thinking: settings.thinking, timeout: settings.timeout)
  }

  /// Mette nei campi i testi riscritti. Un testo che l'utente ha cambiato mentre l'LLM scriveva resta com'è. Prima si
  /// fotografa lo stato (solo l'ultima fotografia), per «Annulla».
  func apply(_ result: MossWriteResult) {
    var applicable: [MossRewrite] = []
    var kept: [String] = []
    for rewrite in result.rewrites {
      if currentText(of: rewrite.kind) == rewrite.original { applicable.append(rewrite) } else { kept.append(rewrite.kind.title) }
    }
    var lines = [result.status]
    if !applicable.isEmpty {
      document.snapshot = MossSnapshot.take(from: document)
      for rewrite in applicable {
        switch rewrite.kind {
        case .summary:
          document.description = rewrite.text
          // Le voci della caption sono ormai nel testo; quelle di medium e genere non passano dall'LLM e restano.
          document.selection = catalog.keepingMeta(document.selection)
        case .meta:
          document.freeMeta = rewrite.text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        case .item(let id, _): update(item: id) { $0.caption = rewrite.text }
        case .tags(let id): update(item: id) { $0.tags = rewrite.text }
        }
      }
    }
    if !kept.isEmpty { lines.append(L.format(.changedMeanwhile, kept.joined(separator: ", "), italian: italian)) }
    status = lines.filter { !$0.isEmpty }.joined(separator: " ")
  }

  private func currentText(of kind: MossPart.Kind) -> String? {
    switch kind {
    case .summary: return document.description.trimmingCharacters(in: .whitespacesAndNewlines)
    case .meta: return document.freeMeta.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
    case .item(let id, _): return document.items.first { $0.id == id }?.caption.trimmingCharacters(in: .whitespacesAndNewlines)
    case .tags(let id): return document.items.first { $0.id == id }?.tagList.joined(separator: ", ")
    }
  }

  /// «Annulla»: rimette i testi di prima (solo l'ultima scrittura).
  func undo() {
    guard let snapshot = document.snapshot else { return }
    var restored = document
    snapshot.restore(into: &restored)
    document = restored
    status = L.text(.undone, italian: italian)
  }

  // MARK: Progetti

  /// Vero mentre la sessione di un progetto viene letta nel tab: i cambi che ne vengono non si riscrivono.
  private var isRestoring = false

  /// L'app ha aperto un progetto: il tab mostra la sessione di quel progetto (`adoptLegacy`: il primo progetto di sempre prende la
  /// sessione che il tab aveva prima).
  func switchProject(folder: URL, adoptLegacy: Bool) {
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
    selectedItem = nil
    reviewOverride = nil
    sizeNotice = nil
    isRestoring = false
  }

  private func persist() {
    guard !isRestoring else { return }
    store.save(MossSession(document: document, openGroups: openGroups.sorted(), openCategories: openCategories.sorted()))
  }
}
