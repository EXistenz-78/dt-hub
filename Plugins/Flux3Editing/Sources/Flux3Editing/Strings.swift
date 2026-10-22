import Foundation

/// Le parole del plug-in, in italiano e in inglese. Un bundle contiene solo la libreria, quindi niente file `.strings`:
/// la tabella è qui (i test controllano che le due lingue siano complete).
enum L {
  enum Key: CaseIterable {
    case title
    case noWindow, undone
    case moveFrom, moveTo, existingTag, removeTag
    case moodboardTitle, startImageTitle, promptTitle, emptyMoodboard, needsStartImage, drawOnReferenceHint, drawOnCanvasHint
    case previousImage, nextImage, imageCounter, proseTitle, proseHint, descriptionPlaceholder, noElements, noDescription
    case kindFromReference, kindNew, kindExisting, kindMove, kindRemove, moveUp, moveDown, removeElement, idLabel
    case undo, writeWithLLM, writing, send, sending, sent, sentWithConflicts, notAnswered
    case problemNoStart, problemNoElements, problemEmptyID, problemEmptyDescription, problemRepeatedID, problemImageMissing
    case sendImages, sendImagesHelp, imagesNotSent
    case clearHelp, clearTitle, clearAction
    case nothingToWrite, writtenCount, failedParts, tagsChanged, changedMeanwhile
    case warningIDNotInProse, warningUnknownReference, warningTooManyImages, imageGone, generationCanvas
  }

  static var systemIsItalian: Bool {
    Locale.preferredLanguages.first?.hasPrefix("it") ?? false
  }

  static func text(_ key: Key, italian: Bool = systemIsItalian) -> String {
    (italian ? it : en)[key] ?? en[key] ?? "\(key)"
  }

  static func isDefined(_ key: Key, italian: Bool) -> Bool { (italian ? it : en)[key] != nil }

  static func format(_ key: Key, _ args: CVarArg..., italian: Bool = systemIsItalian) -> String {
    String(format: text(key, italian: italian), arguments: args)
  }

  private static let en: [Key: String] = [
    .title: "Flux3 Editing",
    .noWindow: "This app does not say where the image sits in the canvas: the whole image is shown fitted to it, so the boxes may not match if it is zoomed or has margins.",
    .undone: "Previous texts restored.",
    .moveFrom: "%@ from", .moveTo: "%@ to", .existingTag: "%@ · existing", .removeTag: "%@ · remove",
    .moodboardTitle: "Moodboard", .startImageTitle: "Start image", .promptTitle: "Prompt",
    .emptyMoodboard: "The Moodboard has no pictures on. Add some in the Control tab (and turn them on) to take objects from them.",
    .needsStartImage: "A start image is needed: add one in the Control tab.",
    .drawOnReferenceHint: "Draw a box on what you want to take.",
    .drawOnCanvasHint: "Draw a box for something new, to keep, move or remove.",
    .previousImage: "Previous picture", .nextImage: "Next picture", .imageCounter: "%d of %d",
    .proseTitle: "Text", .proseHint: "Describe the edit. Cite the pictures as <ref_image_0>, <ref_image_1>… and each element as <id>.",
    .descriptionPlaceholder: "What this element is, or how it changes", .noElements: "No boxes yet.",
    .noDescription: "(no description)",
    .kindFromReference: "From reference", .kindNew: "New", .kindExisting: "Existing", .kindMove: "Move", .kindRemove: "Remove",
    .moveUp: "Move up", .moveDown: "Move down", .removeElement: "Remove this element", .idLabel: "id",
    .undo: "Undo", .writeWithLLM: "Write with LLM", .writing: "Writing…", .send: "Send", .sending: "Sending…",
    .sent: "Prompt sent.", .sentWithConflicts: "Prompt sent. %d conflict(s) waiting in the app.",
    .notAnswered: "The app did not answer.",
    .problemNoStart: "A start image is needed.", .problemNoElements: "Draw at least one box.",
    .problemEmptyID: "An element has no id.", .problemEmptyDescription: "%@ needs a description.",
    .problemRepeatedID: "%@ appears twice: ids must differ.", .problemImageMissing: "%@: its picture is no longer in the Moodboard.",
    .warningIDNotInProse: "%@ is not cited in the text as <%@>.", .warningUnknownReference: "The text cites <ref_image_%d>, which is not in the Moodboard.",
    .warningTooManyImages: "FLUX.3 reads at most ten pictures: the start image and nine from the Moodboard.",
    .imageGone: "Its picture is no longer in the Moodboard.", .generationCanvas: "Canvas %d × %d",
    .sendImages: "Send the cropped pictures to the LLM",
    .sendImagesHelp: "Attaches, for each box drawn on a Moodboard picture, the crop of that box. It needs a model that can read images; otherwise the texts are written without them.",
    .imagesNotSent: "The model could not take the pictures: written from the texts only.",
    .clearHelp: "Clear the text and all the boxes", .clearTitle: "Clear the text and all the boxes?", .clearAction: "Clear",
    .nothingToWrite: "Nothing to write yet.", .writtenCount: "%d text(s) written.",
    .failedParts: "Not rewritten (the original stays): %@.", .tagsChanged: "the LLM changed the placeholders",
    .changedMeanwhile: "Changed while writing, so kept as it is: %@.",
  ]
  private static let it: [Key: String] = [
    .title: "Flux3 Editing",
    .noWindow: "Questa app non dice dove sta l'immagine nel canvas: la vedi intera adattata, quindi i riquadri possono non corrispondere se è ingrandita o ha dei margini.",
    .undone: "Testi precedenti ripristinati.",
    .moveFrom: "%@ da", .moveTo: "%@ a", .existingTag: "%@ · esistente", .removeTag: "%@ · togli",
    .moodboardTitle: "Moodboard", .startImageTitle: "Immagine di partenza", .promptTitle: "Prompt",
    .emptyMoodboard: "Il Moodboard non ha immagini accese. Aggiungile nel tab Control (e accendile) per prenderne degli oggetti.",
    .needsStartImage: "Serve un'immagine di partenza: aggiungila nel tab Control.",
    .drawOnReferenceHint: "Disegna un riquadro su ciò che vuoi prendere.",
    .drawOnCanvasHint: "Disegna un riquadro per qualcosa di nuovo, da tenere, spostare o togliere.",
    .previousImage: "Immagine precedente", .nextImage: "Immagine successiva", .imageCounter: "%d di %d",
    .proseTitle: "Testo", .proseHint: "Descrivi la modifica. Cita le immagini come <ref_image_0>, <ref_image_1>… e ogni elemento come <id>.",
    .descriptionPlaceholder: "Che cos'è questo elemento, o come cambia", .noElements: "Ancora nessun riquadro.",
    .noDescription: "(senza descrizione)",
    .kindFromReference: "Da riferimento", .kindNew: "Nuovo", .kindExisting: "Esistente", .kindMove: "Sposta", .kindRemove: "Togli",
    .moveUp: "Sposta su", .moveDown: "Sposta giù", .removeElement: "Elimina questo elemento", .idLabel: "id",
    .undo: "Annulla", .writeWithLLM: "Scrivi con LLM", .writing: "Scrivo…", .send: "Invia", .sending: "Invio…",
    .sent: "Prompt inviato.", .sentWithConflicts: "Prompt inviato. %d conflitto/i in attesa nell'app.",
    .notAnswered: "L'app non ha risposto.",
    .problemNoStart: "Serve un'immagine di partenza.", .problemNoElements: "Disegna almeno un riquadro.",
    .problemEmptyID: "Un elemento non ha l'id.", .problemEmptyDescription: "%@ ha bisogno di una descrizione.",
    .problemRepeatedID: "%@ compare due volte: gli id devono essere diversi.", .problemImageMissing: "%@: la sua immagine non è più nel Moodboard.",
    .warningIDNotInProse: "%@ non è citato nel testo come <%@>.", .warningUnknownReference: "Il testo cita <ref_image_%d>, che non è nel Moodboard.",
    .warningTooManyImages: "FLUX.3 legge al massimo dieci immagini: quella di partenza e nove del Moodboard.",
    .imageGone: "La sua immagine non è più nel Moodboard.", .generationCanvas: "Canvas %d × %d",
    .sendImages: "Manda i ritagli all'LLM",
    .sendImagesHelp: "Allega, per ogni riquadro disegnato su un'immagine del Moodboard, il ritaglio di quel riquadro. Serve un modello che legga le immagini; altrimenti i testi si scrivono senza.",
    .imagesNotSent: "Il modello non ha potuto prendere le immagini: scritto dai soli testi.",
    .clearHelp: "Pulisci il testo e tutti i riquadri", .clearTitle: "Pulire il testo e tutti i riquadri?", .clearAction: "Pulisci",
    .nothingToWrite: "Non c'è ancora niente da scrivere.", .writtenCount: "%d testo/i scritto/i.",
    .failedParts: "Non riscritti (resta l'originale): %@.", .tagsChanged: "l'LLM ha cambiato i segnaposto",
    .changedMeanwhile: "Cambiati mentre scrivevo, restano come sono: %@.",
  ]
}
