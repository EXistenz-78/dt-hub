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
  /// Dove sta l'immagine di partenza nel canvas (app ≥ 0.3.7); nil se l'app non lo dice.
  @Published private(set) var window: DTHubImageWindow?
  /// L'elemento selezionato sulle tele o nell'elenco (stato della vista: non si ricorda).
  @Published var selected: String?
  @Published var status = ""
  @Published var isSending = false
  /// «Scrivi con LLM» è in corso.
  @Published var isWriting = false
  @Published var active = false
  /// La cartella del progetto aperto (dove stanno `state.json` e `llm/`); nil finché l'app non ha detto il progetto.
  private(set) var projectFolder: URL?
  private var isRestoring = false

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

  func update(context: DTHubContext) {
    refs = RefNumbering.references(moodboard: context.moodboard ?? [], sizes: imageSize)
    startImage = context.startImage.map { URL(fileURLWithPath: $0) }
    startSize = context.startImage.flatMap(imageSize)
    if let width = context.parameters?.width, let height = context.parameters?.height, width > 0, height > 0 {
      generationSize = CGSize(width: width, height: height)
    }
    window = context.startImageWindow
    clampReference()
    if let id = selected, document.element(id) == nil { selected = nil }
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

  func update(element id: String, _ change: (inout EditElement) -> Void) {
    guard let index = document.elements.firstIndex(where: { $0.id == id }) else { return }
    change(&document.elements[index])
  }

  // MARK: Invia e annulla

  var problems: [EditProblem] { EditComposer.problems(document, refs: refs, hasStartImage: startImage != nil) }
  var warnings: [EditWarning] { EditComposer.warnings(document, refs: refs) }
  var sendText: String { EditComposer.text(document, refs: refs) }
  var canSend: Bool { active && !isSending && !isWriting && problems.isEmpty }

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
