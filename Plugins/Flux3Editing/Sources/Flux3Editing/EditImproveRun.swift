import DTHubPluginKit
import Foundation

extension EditState {
  /// Questo punto ha un solo scopo: «Migliora prompt» si fa allo stesso modo dal pulsante e dallo strumento di un agente.
  /// `ask` è `host.askLanguageModelAnswer`; chi chiama ha già messo `isWriting` (così un secondo clic non parte) e controllato `canWrite`.
  func improve(ask: @escaping @MainActor (String, String, DTHubLLMOptions, [String], String?) async -> DTHubLLMAnswer) async {
    status = L.text(.improving, italian: italian)
    let document = self.document
    let (allowed, system, refs) = (allowedTags, writeSystem, self.refs)
    let mode = writeMode
    var pupPictures: [EditPicture] = []
    if case .pup = mode { pupPictures = self.pupPictures() }
    let drawn = llmPictures()
    let leftOut = droppedPictures
    let improver = EditImprover(ask: ask, italian: italian)
    let outcome = await improver.improve(
      document: document, refs: refs, allowedTags: allowed, mode: mode, pupPictures: pupPictures, drawnPictures: drawn,
      standardSystem: system)
    let before = EditSnapshot.take(from: document)
    var wrote = false
    if let pup = outcome.pup {
      wrote = applyPup(pup, original: before)
    } else if let standard = outcome.standard {
      wrote = apply(standard)
      if !leftOut.isEmpty {
        status += " " + L.format(.picturesLeftOut, leftOut.map { "<ref_image_\($0)>" }.joined(separator: ", "), italian: italian)
      }
    }
    if wrote { addNote(outcome.note) }
    if let folder = projectFolder, !outcome.request.isEmpty {
      EditWorkFolder(folder: folder).write(request: outcome.request, answer: outcome.answer, before: before)
    }
    isWriting = false
  }
}
