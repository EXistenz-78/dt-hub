import DTHubPluginKit
import Foundation
import SwiftUI

/// Quello che il tab mostra e modifica.
@MainActor
final class MingState: ObservableObject {
  let data: MingData
  let catalog: MingCatalog
  private var store: MingStore
  /// Dove stava la sessione prima dei progetti: quello che adotta il primo progetto.
  private let legacyStorage: any SessionStorage
  private let shuffler: (MingCatalog, StyleMode) -> Set<String>
  let italian: Bool

  @Published var document: MingDocument { didSet { persist() } }
  @Published var openGroups: Set<String> { didSet { persist() } }
  @Published var openCategories: Set<String> { didSet { persist() } }
  @Published var status = ""
  @Published var isSending = false
  /// «Scrivi con LLM» o «Componi con LLM» è in corso.
  @Published var isWriting = false
  @Published var active = false
  /// Il livello selezionato sul canvas o nell'elenco (stato della vista: non si ricorda).
  @Published var selectedLayer: Int?
  /// La dimensione della Generazione, come l'app l'ha detta per ultima. Non si salva: arriva a ogni avvio.
  @Published private(set) var generationSize: PixelSize?
  /// Avviso sopra il canvas quando il RAPPORTO della dimensione è cambiato (i box restano nelle stesse frazioni).
  @Published private(set) var sizeNotice: String?
  /// Il prompt del campo Prompt della Generazione, come l'app l'ha detto per ultimo (nil: non ancora detto).
  @Published private(set) var generationPrompt: String?
  /// Il prompt della Generazione che l'utente ha già importato o scartato: l'avviso non torna per lo stesso testo.
  @Published private(set) var handledPrompt: String?
  /// Dove si leggono il master prompt e quello dell'utente (a ogni scrittura).
  let promptFolder: DTHubPromptFolder
  /// La cartella del progetto aperto (dove stanno `state.json` e `llm/`); nil finché l'app non ha detto il progetto.
  private(set) var projectFolder: URL?

  init(
    data: MingData = MingData.load(), promptFolder: DTHubPromptFolder = MingPrompts.folder(), store: MingStore = MingStore(),
    italian: Bool = L.systemIsItalian,
    shuffler: @escaping (MingCatalog, StyleMode) -> Set<String> = { catalog, mode in
      var generator = SystemRandomNumberGenerator()
      return MingShuffler.pick(catalog: catalog, mode: mode, using: &generator)
    }
  ) {
    self.data = data
    self.promptFolder = promptFolder
    self.store = store
    legacyStorage = store.storage
    self.italian = italian
    self.shuffler = shuffler
    let catalog = MingCatalog(database: data.database, config: data.config)
    self.catalog = catalog
    let session = store.load()
    var document = session.document
    document.setMode(document.mode, catalog: catalog)
    self.document = document
    openGroups = Set(session.openGroups)
    openCategories = Set(session.openCategories)
    status = (data.warnings.map { Self.text(for: $0) } + MingPrompts.problems(in: promptFolder)).joined(separator: " ")
  }

  private static func text(for warning: DataWarning) -> String {
    switch warning {
    case .unreadable(let file): return "\(file): unreadable"
    case .unknownSchema(let file): return "\(file): unknown layout"
    case .repeatedIDs(let file): return "\(file): repeated ids"
    }
  }

  // MARK: Cosa dice l'app

  private(set) var languageModels: [DTHubLanguageModel] = []
  private(set) var contextFamily: String?
  /// Il Family prompt della famiglia scelta, come l'app lo manda (per comporre); nil se non lo manda.
  private(set) var familyPrompt: String?

  func update(models: [DTHubLanguageModel], family: String?, familyPrompt: String? = nil) {
    languageModels = models
    contextFamily = family
    self.familyPrompt = familyPrompt
  }

  /// Il modello assegnato alla famiglia in Preferenze › LLM (nil: l'app sceglie quello su «tutte le altre»).
  var writeModel: String? { LLMChoice.model(family: contextFamily, languageModels: languageModels) }

  /// L'app ha detto la dimensione della Generazione. Rapporto diverso: i box restano nelle stesse frazioni e compare l'avviso.
  func update(generationSize new: PixelSize?) {
    let old = generationSize
    generationSize = new
    guard let old, let new, old != new, old.isUsable, new.isUsable else { return }
    let oldRatio = Double(old.width) / Double(old.height), newRatio = Double(new.width) / Double(new.height)
    if abs(oldRatio - newRatio) > 0.005, !document.layers.isEmpty, !isApplyingImportSize {
      sizeNotice = L.format(.sizeRatioChanged, old.width, old.height, new.width, new.height, italian: italian)
    }
  }

  func dismissSizeNotice() { sizeNotice = nil }

  /// L'app ha detto il prompt della Generazione (con il contesto, a ogni ritorno sul tab).
  func update(generationPrompt prompt: String?) { generationPrompt = prompt }

  /// Larghezza su altezza della Generazione; un quadrato finché l'app non l'ha detta.
  var canvasAspect: Double {
    guard let size = generationSize, size.isUsable else { return 1 }
    return Double(size.width) / Double(size.height)
  }

  // MARK: Gli elenchi

  func choose(_ termID: String) { document.choose(termID, catalog: catalog) }
  func isChosen(_ termID: String) -> Bool { document.selection.contains(termID) }
  func setMode(_ mode: StyleMode) { document.setMode(mode, catalog: catalog) }
  func shuffle() { document.selection = shuffler(catalog, document.mode) }
  func isOpen(group id: String) -> Bool { openGroups.contains(id) }
  func isOpen(category id: String) -> Bool { openCategories.contains(id) }
  func toggleOpen(group id: String) { if !openGroups.insert(id).inserted { openGroups.remove(id) } }
  func toggleOpen(category id: String) { if !openCategories.insert(id).inserted { openCategories.remove(id) } }

  // MARK: I colori di un livello

  func addColor(to id: Int) {
    guard let layer = document.layers.first(where: { $0.id == id }), layer.colors.count < Palette.elementLimit else { return }
    var generator = SystemRandomNumberGenerator()
    let hex = Palette.random(using: &generator)
    update(layer: id) { $0.colors.append(hex) }
  }

  func setColor(_ text: String, at index: Int, in id: Int) {
    guard let hex = Palette.normalize(text) else { return }
    update(layer: id) { if $0.colors.indices.contains(index) { $0.colors[index] = hex } }
  }

  func removeColor(at index: Int, from id: Int) {
    update(layer: id) { if $0.colors.indices.contains(index) { $0.colors.remove(at: index) } }
  }

  // MARK: I livelli

  func addLayer(kind: MingKind, box: FracBox) {
    let id = document.nextLayerID
    document.nextLayerID += 1
    document.layers.append(
      MingLayer(id: id, kind: kind, description: "", text: "", relation: "", colors: [], box: box, expanded: true))
    selectedLayer = id
  }

  /// Il binding di un campo di testo di un livello. Legge dal documento, non dalla copia con cui la scheda è stata disegnata: una
  /// copia in ritardo restituisce all'editor il testo di prima tra due battute e il cursore salta alla fine.
  func layerBinding(_ id: Int, _ keyPath: WritableKeyPath<MingLayer, String>, fallback: String) -> Binding<String> {
    Binding(
      get: { [unowned self] in document.layers.first { $0.id == id }?[keyPath: keyPath] ?? fallback },
      set: { [unowned self] value in update(layer: id) { $0[keyPath: keyPath] = value } })
  }

  /// Cambia il tipo. Un oggetto che diventa testo tiene la descrizione come aspetto; il testo si scrive a parte.
  func setKind(_ kind: MingKind, for id: Int) { update(layer: id) { $0.kind = kind } }

  func update(layer id: Int, _ change: (inout MingLayer) -> Void) {
    guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
    change(&document.layers[index])
  }

  func removeLayer(_ id: Int) {
    document.layers.removeAll { $0.id == id }
    if selectedLayer == id { selectedLayer = nil }
  }

  /// Sposta un livello di `step` posti nell'elenco (che va dallo sfondo al primo piano).
  func moveLayer(_ id: Int, by step: Int) {
    guard let index = document.layers.firstIndex(where: { $0.id == id }), document.layers.indices.contains(index + step) else { return }
    document.layers.swapAt(index, index + step)
  }

  /// Toglie tutti i livelli e le impostazioni della tela (con Annulla).
  func clearAll() {
    document.snapshot = MingSnapshot.take(from: document)
    document.layers = []
    document.imageStyle = ""
    document.ambientLighting = ""
    selectedLayer = nil
    status = L.text(.cleared, italian: italian)
  }

  // MARK: Il canvas

  @Published var typeMenuLayer: Int?

  var canvasItems: [CanvasItem] {
    document.layers.enumerated().map { CanvasItem(id: $1.id, number: $0 + 1, kind: $1.kind, box: $1.box) }
  }

  func canvasEnd(_ drag: CanvasDrag, geometry: CanvasGeometry) {
    switch drag.mode {
    case .draw:
      typeMenuLayer = nil
      if drag.moved, let box = geometry.result(of: drag) { addLayer(kind: .object, box: box) } else { selectedLayer = nil }
    case .tag(let id):
      if !drag.moved {
        select(id)
        typeMenuLayer = id
      }
    case .move(let id, _), .resize(let id, _, _):
      typeMenuLayer = nil
      select(id)
      if drag.moved, let box = geometry.result(of: drag) { update(layer: id) { $0.box = box } }
    }
  }

  func select(_ id: Int) {
    selectedLayer = id
    update(layer: id) { $0.expanded = true }
  }

  func chooseKind(_ kind: MingKind, for id: Int) {
    setKind(kind, for: id)
    typeMenuLayer = nil
  }

  // MARK: Invia

  var problems: [MingProblem] { MingComposer.problems(document, size: generationSize) }

  /// Il JSON che «Invia» manda; nil senza una dimensione utilizzabile.
  func currentJSON() -> String? {
    guard let size = generationSize, size.isUsable else { return nil }
    return MingComposer.json(document, catalog: catalog, size: size)
  }

  var sendHint: String? {
    guard let problem = problems.first(where: { $0 == .unknownSize }) ?? problems.first else { return nil }
    switch problem {
    case .unknownSize: return L.text(.problemUnknownSize, italian: italian)
    case .noLayers: return L.text(.problemNoLayers, italian: italian)
    case .emptyDescription(let id): return L.format(.problemEmptyDescription, number(of: id), italian: italian)
    case .emptyText(let id): return L.format(.problemEmptyText, number(of: id), italian: italian)
    }
  }

  /// Il numero con cui il livello compare sull'etichetta (la posizione nell'elenco, da 1).
  func number(of id: Int) -> Int { (document.layers.firstIndex { $0.id == id } ?? 0) + 1 }

  /// La posizione di un livello come la scrive Ming: `cx, cy, w, h`.
  func positionText(of id: Int) -> String {
    guard let layer = document.layers.first(where: { $0.id == id }) else { return "" }
    return MingGeometry.coordinates(layer.box)
  }

  /// L'utente ha scritto una posizione: se si legge, il box cambia; altrimenti resta com'è.
  func setPosition(_ text: String, of id: Int) {
    guard let box = MingGeometry.parse(text) else { return }
    update(layer: id) { $0.box = box }
  }

  var statusLines: [String] { [status, canSend ? nil : sendHint].compactMap { $0 }.filter { !$0.isEmpty } }

  var canSend: Bool { active && !isSending && !isWriting && problems.isEmpty }

  // MARK: Importa

  /// Il prompt della Generazione è un JSON di Ming diverso da quello che il tab manderebbe, e l'utente non l'ha già importato o
  /// scartato: sopra il canvas compare l'offerta di importarlo.
  var importOffer: Bool {
    guard let prompt = generationPrompt, !isWriting, prompt != handledPrompt, MingImporter.looksImportable(prompt) else { return false }
    return normalizedJSON(prompt) != currentJSON().map(normalizedJSON)
  }

  private func normalizedJSON(_ text: String) -> String { text.filter { !$0.isWhitespace } }

  /// Mentre l'import cambia la dimensione della Generazione, il cambio di forma non è una sorpresa: niente avviso.
  private var isApplyingImportSize = false

  /// Mette nel tab un JSON di Ming: i livelli, stile e luce (tutto il resto si toglie). Con Annulla. Restituisce la dimensione
  /// che la Generazione dovrebbe avere per la forma del JSON, se è diversa da quella di adesso.
  @discardableResult
  func apply(imported: MingImported, source: String) -> PixelSize? {
    document.snapshot = MingSnapshot.take(from: document)
    var layers = imported.layers
    var next = 1
    for index in layers.indices {
      layers[index].id = next
      next += 1
    }
    document.layers = layers
    document.nextLayerID = next
    document.imageStyle = imported.imageStyle
    document.ambientLighting = imported.ambientLighting
    // Le voci scelte sono già nel testo importato: si tolgono, altrimenti comparirebbero due volte.
    document.selection = []
    selectedLayer = nil
    typeMenuLayer = nil
    sizeNotice = nil
    var lines = [L.format(.importedCount, layers.count, source, italian: italian)]
    if !imported.warnings.isEmpty { lines.append(imported.warnings.joined(separator: " ")) }
    status = lines.joined(separator: " ")
    guard let shape = imported.shape else { return nil }
    let wanted = MingGeometry.size(for: shape, keepingLongSideOf: generationSize)
    if let current = generationSize, current.isUsable {
      let currentRatio = Double(current.width) / Double(current.height)
      if case .ratio = shape, abs(currentRatio - shape.ratio) < 0.01 { return nil }
      if current == wanted { return nil }
    }
    return wanted
  }

  /// L'import dal campo Prompt della Generazione (il pulsante e lo strumento MCP). Restituisce la dimensione da chiedere all'app
  /// o un errore da mostrare.
  func importFromGeneration() -> Result<PixelSize?, MingImporter.Failure> {
    guard let prompt = generationPrompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      status = L.text(.importNoPrompt, italian: italian)
      return .failure(MingImporter.Failure(reason: "The Generation prompt is empty."))
    }
    handledPrompt = prompt
    switch MingImporter.parse(prompt) {
    case .success(let imported): return .success(apply(imported: imported, source: L.text(.sourceGeneration, italian: italian)))
    case .failure(let failure):
      status = L.format(.importFailed, failure.reason, italian: italian)
      return .failure(failure)
    }
  }

  func dismissImportOffer() { handledPrompt = generationPrompt }

  /// L'app ha cambiato la dimensione come chiesto dall'import.
  func beginImportSize() { isApplyingImportSize = true }
  func endImportSize() { isApplyingImportSize = false }

  // MARK: Scrivi e componi con LLM

  var hasWritableContent: Bool { !MingBrief.parts(from: document, catalog: catalog).isEmpty }

  var canWrite: Bool { active && !isWriting && !isSending && hasWritableContent }
  var canCompose: Bool {
    active && !isWriting && !isSending && !document.idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && generationSize?.isUsable == true
  }
  var canUndo: Bool { document.snapshot != nil && !isWriting }

  var writeSystem: String { MingPrompts.system(in: promptFolder) }
  var composeSystem: String { MingPrompts.composeSystem(familyPrompt: familyPrompt, in: promptFolder) }
  var writeOptions: DTHubLLMOptions {
    let settings = data.config.options
    return DTHubLLMOptions(
      temperature: settings.temperature, maxTokens: settings.maxTokens, thinking: settings.thinking, timeout: settings.timeout)
  }

  /// La richiesta di «Componi con LLM»; nil se non si può comporre.
  func composeRequest() -> String? {
    guard let size = generationSize, size.isUsable else { return nil }
    let idea = document.idea.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !idea.isEmpty else { return nil }
    return MingBrief.composeMessage(
      idea: idea, styleLines: catalog.styleLines(document.selection), lightingLines: catalog.lightingLines(document.selection),
      size: size, currentJSON: document.layers.isEmpty ? nil : currentJSON())
  }

  /// Mette nei campi i testi riscritti. Un testo che l'utente ha cambiato mentre l'LLM scriveva resta com'è.
  func apply(_ result: MingWriteResult) {
    var applicable: [MingRewrite] = []
    var kept: [String] = []
    for rewrite in result.rewrites {
      if currentText(of: rewrite.kind) == rewrite.original { applicable.append(rewrite) } else { kept.append(rewrite.kind.title) }
    }
    var lines = [result.status]
    if !applicable.isEmpty {
      document.snapshot = MingSnapshot.take(from: document)
      for rewrite in applicable {
        switch rewrite.kind {
        case .imageStyle:
          document.imageStyle = rewrite.text
          // Le voci sono ormai nel testo: restano scelte solo quelle della luce (e viceversa sotto).
          document.selection = document.selection.filter { id in catalog.styleTerms([id]).isEmpty }
        case .ambientLighting:
          document.ambientLighting = rewrite.text
          document.selection = document.selection.filter { id in catalog.lightingTerms([id]).isEmpty }
        case .layer(let id, _): update(layer: id) { $0.description = rewrite.text }
        case .relation(let id): update(layer: id) { $0.relation = rewrite.text }
        }
      }
    }
    if !kept.isEmpty { lines.append(L.format(.changedMeanwhile, kept.joined(separator: ", "), italian: italian)) }
    status = lines.filter { !$0.isEmpty }.joined(separator: " ")
  }

  private func currentText(of kind: MingPart.Kind) -> String? {
    switch kind {
    case .imageStyle: return document.imageStyle.trimmingCharacters(in: .whitespacesAndNewlines)
    case .ambientLighting: return document.ambientLighting.trimmingCharacters(in: .whitespacesAndNewlines)
    case .layer(let id, _): return document.layers.first { $0.id == id }?.description.trimmingCharacters(in: .whitespacesAndNewlines)
    case .relation(let id): return document.layers.first { $0.id == id }?.relation.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  /// «Annulla»: rimette il lavoro di prima (solo l'ultima scrittura, composizione o importazione).
  func undo() {
    guard let snapshot = document.snapshot else { return }
    var restored = document
    snapshot.restore(into: &restored)
    document = restored
    selectedLayer = nil
    status = L.text(.undone, italian: italian)
  }

  // MARK: Progetti

  private var isRestoring = false

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
    selectedLayer = nil
    sizeNotice = nil
    isRestoring = false
  }

  private func persist() {
    guard !isRestoring else { return }
    store.save(MingSession(document: document, openGroups: openGroups.sorted(), openCategories: openCategories.sorted()))
  }
}
