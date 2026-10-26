import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here.
enum L {
  enum Key: CaseIterable {
    case canvasTitle, guides, clearAll, clearConfirm, clearConfirmMessage, cancel
    case stickersTitle, yaw, pitch, rotation, fieldOfView, verticalFieldOfView, opacity, duplicate, delete, add, toggleVisible
    case croppedPhoto, unreadableFile, openProjectFirst, dropHere
    case seamDescription, seamButton, seamPipelineName, seamReady, seamDone, seamStopped, seamClosed, seamFailed, seamNoPicture, seamWrongSize, seamUnreadablePicture
    case seamNoResult, seamUnreadable, seamNotTwoToOne, seamHeight, seamTooBig
    case cutoutSize, extract, actionStart, actionMoodboard, actionSave, actionSticker, actionPanorama, cutoutNothing, putBackOff, montageDescription
    case putBackNoCutout, putBackNoPatch, putBackWrongProportion, putBackPatchMissing, putBackNoPanorama, putBackPanoramaMissing, megapixels
    case viewPlane, viewSphere, sourceCanvas, sourceResult, resetView, noResultYet, resultUnreadable, resultNotTwoToOne
    case modeNormal, modeFast, send, noVisibleSticker, sendFailed, noAnswerFromApp, notBaseWarning
    case promptTitle, promptPlaceholder, improve, improving, undo, words, emptyDescription, answerNotEnglish, answerRejected, improveStale
  }

  static var systemIsItalian: Bool { Locale.preferredLanguages.first?.hasPrefix("it") ?? false }

  static func text(_ key: Key, italian: Bool = systemIsItalian) -> String { (italian ? it : en)[key] ?? en[key] ?? "\(key)" }

  /// Whether the word is in the table of that language (the tests check both are complete).
  static func isDefined(_ key: Key, italian: Bool) -> Bool { (italian ? it : en)[key] != nil }

  static func format(_ key: Key, _ args: CVarArg..., italian: Bool = systemIsItalian) -> String {
    String(format: text(key, italian: italian), arguments: args)
  }

  private static let en: [Key: String] = [
    .canvasTitle: "360° canvas", .guides: "Guides", .clearAll: "Remove all stickers", .clearConfirm: "Remove all",
    .clearConfirmMessage: "Remove all the stickers from the canvas?", .cancel: "Cancel",
    .stickersTitle: "Stickers", .yaw: "Yaw (°)", .pitch: "Pitch (°)", .rotation: "Rotation (°)", .fieldOfView: "Horizontal FOV (°)",
    .verticalFieldOfView: "Vertical FOV (°)", .opacity: "Opacity", .duplicate: "Duplicate", .delete: "Delete", .add: "Add picture",
    .toggleVisible: "Show or hide", .croppedPhoto: "“%@” looks cropped: its focal length was not used.",
    .unreadableFile: "“%@” could not be read.", .openProjectFirst: "Open a project first.", .dropHere: "Drop pictures here",
    .seamDescription: "Seam corrected · band of %d px", .seamButton: "Fix the seam", .seamPipelineName: "Panorama 360 · seam",
    .seamReady: "Ready: press RUN in DT Hub.", .seamDone: "Seam corrected: the panorama is in the Results.",
    .seamStopped: "Stopped: the seam was not changed.", .seamClosed: "The correction was closed: the seam was not changed.",
    .seamFailed: "The pass failed: the seam was not changed.", .seamNoPicture: "DT Hub did not send the picture it made: the seam was not changed.",
    .seamWrongSize: "The picture made is not the size of the pass: the seam was not changed.",
    .seamUnreadablePicture: "The picture made cannot be read: the seam was not changed.",
    .seamNoResult: "There is no result to fix yet.", .seamUnreadable: "The last result's file cannot be read.",
    .seamNotTwoToOne: "The last result is not 2:1.", .seamHeight: "The height of the last result is not a multiple of 64.",
    .seamTooBig: "The last result is too big: the central square would pass 2048 px.",
    .cutoutSize: "Size", .extract: "Extract", .actionStart: "Use as start image", .actionMoodboard: "Add to Moodboard", .actionSave: "Save…",
    .actionSticker: "Put back as a sticker", .actionPanorama: "Put back in the panorama (goes to the Results)",
    .cutoutNothing: "Extract the view first.", .putBackOff: "The retouch cannot be put back.",
    .montageDescription: "Montage · cutout put back at yaw %.0f° pitch %.0f° FOV %.0f°",
    .putBackNoCutout: "Extract a view first.", .putBackNoPatch: "Make the retouch first: a RUN on the cutout.",
    .putBackWrongProportion: "The retouch is not 4:3 like the cutout: make it at the size of the cutout.", .putBackPatchMissing: "The retouch's file cannot be read.",
    .putBackNoPanorama: "There was no result when the cutout was taken, so there is no panorama to paste it on.",
    .putBackPanoramaMissing: "The panorama the cutout was taken from is not there any more.", .megapixels: "MP",
    .viewPlane: "Plane", .viewSphere: "Sphere", .sourceCanvas: "Canvas", .sourceResult: "Result", .resetView: "Look straight ahead",
    .noResultYet: "No result yet.\nRUN and it will show here.", .resultUnreadable: "The last result's file cannot be read.",
    .resultNotTwoToOne: "The last result is not 2:1: it is shown as a panorama all the same.",
    .modeNormal: "Normal", .modeFast: "Fast", .send: "Send to Generation",
    .noVisibleSticker: "Add at least one visible sticker.", .sendFailed: "The panorama could not be drawn.",
    .noAnswerFromApp: "No answer from DT Hub.",
    .notBaseWarning: "The model is not a Base one: the 360° LoRA works only with the Base models.",
    .promptTitle: "Prompt", .promptPlaceholder: "Describe the place: light, season, style…", .improve: "Improve prompt",
    .improving: "Improving…", .undo: "Undo", .words: "%d words", .emptyDescription: "Write a description first.",
    .answerNotEnglish: "The language model did not answer in English: the description was left as it was.",
    .answerRejected: "The language model's answer could not be used: the description was left as it was.",
    .improveStale: "The description changed while the language model was working: its answer was dropped.",
  ]

  private static let it: [Key: String] = [
    .canvasTitle: "Tela 360°", .guides: "Guide", .clearAll: "Cancella tutti gli sticker", .clearConfirm: "Cancella tutti",
    .clearConfirmMessage: "Cancellare tutti gli sticker dalla tela?", .cancel: "Annulla",
    .stickersTitle: "Sticker", .yaw: "Yaw (°)", .pitch: "Pitch (°)", .rotation: "Rotazione (°)", .fieldOfView: "FOV orizzontale (°)",
    .verticalFieldOfView: "FOV verticale (°)", .opacity: "Opacità", .duplicate: "Duplica", .delete: "Elimina", .add: "Aggiungi immagine",
    .toggleVisible: "Mostra o nascondi", .croppedPhoto: "«%@» sembra ritagliata: la focale non è stata usata.",
    .unreadableFile: "«%@» non si può leggere.", .openProjectFirst: "Apri prima un progetto.", .dropHere: "Rilascia le immagini qui",
    .seamDescription: "Giunzione corretta · fascia di %d px", .seamButton: "Correggi giunzione", .seamPipelineName: "Panorama 360 · giunzione",
    .seamReady: "Pronto: premi RUN in DT Hub.", .seamDone: "Giunzione corretta: il panorama è nei Risultati.",
    .seamStopped: "Interrotto: la giunzione non è stata modificata.", .seamClosed: "La correzione è stata chiusa: la giunzione non è stata modificata.",
    .seamFailed: "Il passo è fallito: la giunzione non è stata modificata.",
    .seamNoPicture: "DT Hub non ha mandato l'immagine generata: la giunzione non è stata modificata.",
    .seamWrongSize: "L'immagine generata non ha la dimensione del passo: la giunzione non è stata modificata.",
    .seamUnreadablePicture: "L'immagine generata non si legge: la giunzione non è stata modificata.",
    .seamNoResult: "Non c'è ancora un risultato da correggere.", .seamUnreadable: "Il file dell'ultimo risultato non si legge.",
    .seamNotTwoToOne: "L'ultimo risultato non è 2:1.", .seamHeight: "L'altezza dell'ultimo risultato non è un multiplo di 64.",
    .seamTooBig: "L'ultimo risultato è troppo grande: il quadrato centrale supererebbe 2048 px.",
    .cutoutSize: "Dimensione", .extract: "Estrai", .actionStart: "Usa come immagine di partenza", .actionMoodboard: "Aggiungi al Moodboard",
    .actionSave: "Salva…", .actionSticker: "Rimetti come sticker", .actionPanorama: "Rimetti nel panorama (va ai Risultati)",
    .cutoutNothing: "Estrai prima la vista.", .putBackOff: "Il ritocco non si può rimettere.",
    .montageDescription: "Montaggio · ritaglio rimesso a yaw %.0f° pitch %.0f° FOV %.0f°",
    .putBackNoCutout: "Estrai prima una vista.", .putBackNoPatch: "Fai prima il ritocco: un RUN sul ritaglio.",
    .putBackWrongProportion: "Il ritocco non è 4:3 come il ritaglio: fallo alla dimensione del ritaglio.", .putBackPatchMissing: "Il file del ritocco non si legge.",
    .putBackNoPanorama: "Quando hai estratto non c'era un risultato: non c'è un panorama su cui incollarlo.",
    .putBackPanoramaMissing: "Il panorama da cui hai estratto non c'è più.", .megapixels: "MP",
    .viewPlane: "Piano", .viewSphere: "Sfera", .sourceCanvas: "Canvas", .sourceResult: "Risultato", .resetView: "Riporta la vista davanti",
    .noResultYet: "Nessun risultato ancora.\nFai un RUN e comparirà qui.", .resultUnreadable: "Il file dell'ultimo risultato non si legge.",
    .resultNotTwoToOne: "L'ultimo risultato non è 2:1: lo mostro lo stesso come panorama.",
    .modeNormal: "Normale", .modeFast: "Veloce", .send: "Invia a Generazione",
    .noVisibleSticker: "Aggiungi almeno uno sticker visibile.", .sendFailed: "Non è stato possibile disegnare il panorama.",
    .noAnswerFromApp: "Nessuna risposta da DT Hub.",
    .notBaseWarning: "Il modello non è un Base: il LoRA 360° funziona solo con i modelli Base.",
    .promptTitle: "Prompt", .promptPlaceholder: "Descrivi il luogo: luce, stagione, stile…", .improve: "Migliora prompt",
    .improving: "Miglioro…", .undo: "Annulla", .words: "%d parole", .emptyDescription: "Scrivi prima una descrizione.",
    .answerNotEnglish: "L'LLM non ha risposto in inglese: la descrizione è rimasta com'era.",
    .answerRejected: "La risposta dell'LLM non si può usare: la descrizione è rimasta com'era.",
    .improveStale: "La descrizione è cambiata mentre l'LLM lavorava: la sua risposta è stata scartata.",
  ]
}
