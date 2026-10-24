import DTHubPluginKit
import Foundation
import SwiftUI

/// Quello che il tab mostra e modifica.
@MainActor
final class EditState: ObservableObject {
  private var store: EditStore
  /// Dove stava la sessione prima dei progetti: quello che adotta il primo progetto.
  private let legacyStorage: any EditStorage
  private let imageSize: (String) -> CGSize?
  let italian: Bool

  @Published var document: EditDocument { didSet { persist() } }
  /// Le immagini accese del Moodboard, numerate (`ref_image_1…`).
  @Published private(set) var refs: [RefImage] = []
  @Published private(set) var startImage: URL?
  @Published private(set) var startSize: CGSize?
  /// La dimensione della Generazione, come l'app l'ha detta per ultima: il canvas di uscita.
  @Published private(set) var generationSize: CGSize?
  /// Dove sta l'immagine di partenza nel canvas (app ≥ 0.4.0); nil se l'app non lo dice.
  @Published private(set) var window: DTHubImageWindow?
  /// L'elemento selezionato sulle tele o nell'elenco (stato della vista: non si ricorda).
  @Published var selected: String?
  @Published var status = ""
  @Published var isSending = false
  /// «Migliora prompt» è in corso.
  @Published var isWriting = false
  @Published var active = false
  /// La cartella del progetto aperto (dove stanno `state.json` e `llm/`); nil finché l'app non ha detto il progetto.
  private(set) var projectFolder: URL?
  private var isRestoring = false
  /// La cartella per scambiare file con l'app (i ritagli per l'LLM): quella del contesto.
  private(set) var tempFolder: URL?

  init(
    store: EditStore = EditStore(), italian: Bool = L.systemIsItalian,
    imageSize: @escaping (String) -> CGSize? = { ImageSizes.read(path: $0) }
  ) {
    self.store = store
    legacyStorage = store.storage
    self.italian = italian
    self.imageSize = imageSize
    document = store.load().document
  }

  // MARK: Cosa dice l'app

  /// I modelli di linguaggio e la famiglia del modello d'immagine, per scegliere come scrive «Migliora prompt».
  private(set) var languageModels: [DTHubLanguageModel] = []
  private(set) var contextFamily: String?

  var writeMode: WriteMode {
    EditModelChoice.mode(family: contextFamily, models: languageModels) { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
  }

  func update(context: DTHubContext) {
    refs = RefNumbering.references(moodboard: context.moodboard ?? [], sizes: imageSize)
    startImage = context.startImage.map { URL(fileURLWithPath: $0) }
    startSize = context.startImage.flatMap(imageSize)
    if let width = context.parameters?.width, let height = context.parameters?.height, width > 0, height > 0 {
      generationSize = CGSize(width: width, height: height)
    }
    window = context.startImageWindow
    languageModels = context.languageModels ?? []
    contextFamily = context.family
    tempFolder = URL(fileURLWithPath: context.tempFolder, isDirectory: true)
    clampReference()
    if let id = selected, document.element(id) == nil { selected = nil }
  }

  /// Il colore di ogni id nel testo (lo stesso del riquadro e della scheda).
  var tagColors: [String: Int] { Dictionary(document.elements.map { ($0.id, $0.colorIndex) }, uniquingKeysWith: { first, _ in first }) }

  private var picturePlan: EditPicturePlan { EditPictures.plan(document: document, refs: refs, hasStartImage: startImage != nil) }

  /// I numeri delle reference usate che non entrano nel tetto delle immagini (partenza più cinque).
  var droppedPictures: [Int] { picturePlan.dropped }

  /// Le immagini da mandare all'LLM (sempre): quella di partenza come la tela di uscita e le reference
  /// usate intere, con i riquadri disegnati, scritte nella cartella temporanea. Un'immagine che non si legge si salta.
  func llmPictures() -> [EditPicture] {
    guard let tempFolder else { return [] }
    return picturePlan.pictures.compactMap { planned in
      let source: (path: String, geometry: StageGeometry)
      if planned.role == .start {
        guard let startImage else { return nil }
        source = (startImage.path, startGeometry)
      } else {
        guard let ref = refs.first(where: { $0.number == planned.number }) else { return nil }
        source = (ref.path, referenceGeometry(of: ref))
      }
      guard let path = EditOverlay.render(
        imagePath: source.path, geometry: source.geometry, boxes: planned.boxes, to: tempFolder, name: "\(planned.number)")
      else { return nil }
      return EditPicture(number: planned.number, role: planned.role, path: path)
    }
  }

  /// Un'app che non manda `startImageWindow`: si dice, non si nasconde (spec §4).
  var windowNote: String? { startImage != nil && window == nil ? L.text(.noWindow, italian: italian) : nil }

  // MARK: Le tele

  var startGeometry: StageGeometry {
    StageGeometry(canvas: generationSize, image: startSize ?? .zero, window: window)
  }

  func referenceGeometry(of ref: RefImage) -> StageGeometry { .plain(image: ref.size) }

  var currentReference: RefImage? {
    refs.indices.contains(document.referenceIndex) ? refs[document.referenceIndex] : nil
  }

  func showReference(by step: Int) {
    guard !refs.isEmpty else { return }
    document.referenceIndex = min(max(document.referenceIndex + step, 0), refs.count - 1)
  }

  private func clampReference() {
    let clamped = refs.isEmpty ? 0 : min(max(document.referenceIndex, 0), refs.count - 1)
    if clamped != document.referenceIndex { document.referenceIndex = clamped }
  }

  /// Gli elementi «da riferimento» dell'immagine mostrata (le loro origini stanno sulla sua tela).
  var elementsOnShownReference: [EditElement] {
    guard let ref = currentReference else { return [] }
    return document.elements.filter { $0.kind == .fromReference && $0.refFile == ref.fileName }
  }

  // MARK: Disegnare e selezionare

  func drawOnReference(_ box: BBox) {
    guard let ref = currentReference else { return }
    document.draw(onReference: ref.fileName, box: box)
    selected = document.elements.last?.id
  }

  func drawOnCanvas(_ box: BBox) {
    document.draw(onCanvas: box)
    selected = document.elements.last?.id
  }

  func select(_ id: String?) { selected = id }

  /// Il nome di un elemento cambia (la selezione lo segue).
  func rename(_ id: String, to newID: String) {
    guard newID != id else { return }
    update(element: id) { $0.id = newID }
    if selected == id { selected = newID }
  }

  /// La frase di partenza da sola non è un testo da scrivere.
  private var proseIsEdited: Bool {
    let prose = document.prose.trimmingCharacters(in: .whitespacesAndNewlines)
    return !prose.isEmpty && prose != EditDocument.defaultProse.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// «Pulisci» ha qualcosa da togliere: dei riquadri o un testo diverso da quello di partenza.
  var canClear: Bool { !document.elements.isEmpty || document.prose != EditDocument.defaultProse }

  /// «Pulisci»: il tab torna come nuovo.
  func clear() {
    document.clear()
    selected = nil
    status = ""
  }

  /// «Migliora prompt» ha qualcosa da scrivere: un testo o la descrizione di un riquadro.
  var hasWritableContent: Bool {
    proseIsEdited
      || document.elements.contains { !$0.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  var canWrite: Bool { active && !isWriting && !isSending && hasWritableContent }

  func update(element id: String, _ change: (inout EditElement) -> Void) {
    guard let index = document.elements.firstIndex(where: { $0.id == id }) else { return }
    change(&document.elements[index])
  }

  // MARK: Invia e annulla

  var problems: [EditProblem] { EditComposer.problems(document, refs: refs, hasStartImage: startImage != nil) }
  var warnings: [EditWarning] { EditComposer.warnings(document, refs: refs) }
  var sendText: String { EditComposer.text(document, refs: refs) }

  /// I problemi e gli avvisi a parole, per le righe sotto i pulsanti.
  var problemLines: [String] {
    problems.map { problem in
      switch problem {
      case .noStartImage: return L.text(.problemNoStart, italian: italian)
      case .noElements: return L.text(.problemNoElements, italian: italian)
      case .emptyID: return L.text(.problemEmptyID, italian: italian)
      case .emptyDescription(let id): return L.format(.problemEmptyDescription, id, italian: italian)
      case .repeatedID(let id): return L.format(.problemRepeatedID, id, italian: italian)
      case .imageMissing(let id): return L.format(.problemImageMissing, id, italian: italian)
      }
    }
  }

  var warningLines: [String] {
    warnings.map { warning in
      switch warning {
      case .idNotInProse(let id): return L.format(.warningIDNotInProse, id, id, italian: italian)
      case .unknownReferenceInProse(let n): return L.format(.warningUnknownReference, n, italian: italian)
      case .tooManyImages: return L.text(.warningTooManyImages, italian: italian)
      }
    }
  }
  var canSend: Bool { active && !isSending && !isWriting && problems.isEmpty }

  /// I segnaposto che la prosa può citare: gli id degli elementi e le immagini (`ref_image_0…`).
  var allowedTags: Set<String> {
    Set(document.elements.map(\.id)).union(["ref_image_\(RefNumbering.startImageNumber)"]).union(refs.map { "ref_image_\($0.number)" })
  }

  var writeSystem: String { EditPrompts.system() }

  /// Mette nei campi i testi riscritti. Un testo che l'utente ha cambiato mentre l'LLM scriveva resta com'è. Prima si
  /// fotografa lo stato (solo l'ultima fotografia), per «Annulla».
  func apply(_ result: EditWriteResult) {
    var applicable: [EditRewrite] = []
    var kept: [String] = []
    for rewrite in result.rewrites {
      if currentText(of: rewrite.kind) == rewrite.original { applicable.append(rewrite) } else { kept.append(rewrite.kind.title) }
    }
    var lines = [result.status]
    if !applicable.isEmpty {
      takeSnapshot()
      for rewrite in applicable {
        switch rewrite.kind {
        case .prose: document.prose = rewrite.text
        case .element(let id): update(element: id) { $0.desc = rewrite.text }
        }
      }
    }
    if !kept.isEmpty { lines.append(L.format(.changedMeanwhile, kept.joined(separator: ", "), italian: italian)) }
    status = lines.filter { !$0.isEmpty }.joined(separator: " ")
  }

  private func currentText(of kind: EditPart.Kind) -> String? {
    switch kind {
    case .prose: return document.prose.trimmingCharacters(in: .whitespacesAndNewlines)
    case .element(let id): return document.element(id)?.desc.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  var canUndo: Bool { document.snapshot != nil && !isWriting }

  /// Fotografa i testi (solo l'ultima fotografia), prima che una scrittura li sostituisca.
  func takeSnapshot() { document.snapshot = EditSnapshot.take(from: document) }

  /// «Annulla»: rimette i testi di prima (solo l'ultima scrittura).
  func undo() {
    guard let snapshot = document.snapshot else { return }
    var restored = document
    snapshot.restore(into: &restored)
    document = restored
    status = L.text(.undone, italian: italian)
  }

  // MARK: Progetti

  /// L'app ha aperto un progetto: il tab mostra la sessione di quel progetto (`adoptLegacy`: il primo progetto di sempre
  /// prende la sessione che il tab aveva prima).
  func switchProject(folder: URL, adoptLegacy: Bool) {
    projectFolder = folder
    store.storage = FileStorage(folder: folder)
    if adoptLegacy { store.adoptLegacy(from: legacyStorage) }
    isRestoring = true
    document = store.load().document
    selected = nil
    isRestoring = false
    clampReference()
  }

  private func persist() {
    guard !isRestoring else { return }
    store.save(EditSession(document: document))
  }
}
