import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no `.strings` files: the table is here.
enum L {
  enum Key: CaseIterable {
    case moodboardTitle, add, toggleVisible, delete, unreadableFile, openProjectFirst, dropHere, imageMissing
    case promptTitle, promptPlaceholder, improve, improving, undo, words, emptyDescription, answerNotEnglish, answerRejected, improveStale
    case sizeLabel, sizeUp, sizeDown
    case send, noVisibleImage, sendFailed, noAnswerFromApp, pipelineName, pipelineReady, modelNote
    case resultCorrected, resultRaw, runStopped, runClosed, runFailed, runNoPicture, runWrongSize, runUnreadable, runDone
    case viewerTitle, fixSeam, seamNoResult, seamUnreadable, seamNotTwoToOne, seamSize, seamTooBig, seamPipelineName, seamReady
    case noResultYet, resetView, dropResult
  }

  static var systemIsItalian: Bool { Locale.preferredLanguages.first?.hasPrefix("it") ?? false }

  static func text(_ key: Key, italian: Bool = systemIsItalian) -> String { (italian ? it : en)[key] ?? en[key] ?? "\(key)" }

  /// Whether the word is in the table of that language (the tests check both are complete).
  static func isDefined(_ key: Key, italian: Bool) -> Bool { (italian ? it : en)[key] != nil }

  static func format(_ key: Key, _ args: CVarArg..., italian: Bool = systemIsItalian) -> String {
    String(format: text(key, italian: italian), arguments: args)
  }

  private static let en: [Key: String] = [
    .moodboardTitle: "Moodboard", .add: "Add picture", .toggleVisible: "Show or hide", .delete: "Delete",
    .unreadableFile: "“%@” could not be read.", .openProjectFirst: "Open a project first.", .dropHere: "Drop pictures here",
    .imageMissing: "The file of “%@” is gone: remove it and add it again.",
    .promptTitle: "Prompt", .promptPlaceholder: "Describe the place (light, season, style): optional",
    .improve: "Improve prompt", .improving: "Improving…", .undo: "Undo", .words: "%d words",
    .emptyDescription: "Write a few words first, or add a picture.", .answerNotEnglish: "The model did not answer in English: try again.",
    .answerRejected: "The model's answer cannot be used: try again.", .improveStale: "The text changed meanwhile: the answer was dropped.",
    .sizeLabel: "Size", .sizeUp: "Larger", .sizeDown: "Smaller",
    .send: "Send to Generation", .noVisibleImage: "Add at least one picture (and leave its eye on).",
    .sendFailed: "The pictures could not be prepared.", .noAnswerFromApp: "DT Hub did not answer.",
    .pipelineName: "Pano 360 F3", .pipelineReady: "Ready: press RUN in DT Hub.",
    .modelNote: "Ready: the presets were saved with the model «%@»: choose it in the DT Hub header, then press RUN.",
    .resultCorrected: "Pano 360 F3 · seam corrected", .resultRaw: "Pano 360 F3 · without the seam correction",
    .runStopped: "Stopped: nothing was changed.", .runClosed: "The run was closed: nothing was changed.",
    .runFailed: "The pass failed: nothing was changed.", .runNoPicture: "DT Hub did not send the picture it made.",
    .runWrongSize: "The picture made is not the size of the pass (is HiRes on in the preset?).",
    .runUnreadable: "The picture made cannot be read.", .runDone: "Done: the panorama is in the Results.",
    .viewerTitle: "Viewer", .fixSeam: "Fix the seam", .seamNoResult: "There is no result to fix yet.",
    .seamUnreadable: "The picture's file cannot be read.", .seamNotTwoToOne: "The picture is not 2:1.",
    .seamSize: "The height of the picture is not a multiple of 64.", .seamTooBig: "The picture is too tall: the limit is 4096 px.",
    .seamPipelineName: "Pano 360 F3 · seam", .seamReady: "Ready: press RUN in DT Hub.",
    .noResultYet: "No panorama yet", .resetView: "Look straight ahead", .dropResult: "Drop a picture to look at it",
  ]

  private static let it: [Key: String] = [
    .moodboardTitle: "Moodboard", .add: "Aggiungi immagine", .toggleVisible: "Mostra o nascondi", .delete: "Elimina",
    .unreadableFile: "«%@» non si può leggere.", .openProjectFirst: "Apri prima un progetto.", .dropHere: "Trascina qui le immagini",
    .imageMissing: "Il file di «%@» non c'è più: toglila e aggiungila di nuovo.",
    .promptTitle: "Prompt", .promptPlaceholder: "Descrivi il luogo (luce, stagione, stile): facoltativo",
    .improve: "Migliora prompt", .improving: "Miglioro…", .undo: "Annulla", .words: "%d parole",
    .emptyDescription: "Scrivi prima qualche parola, oppure aggiungi un'immagine.",
    .answerNotEnglish: "Il modello non ha risposto in inglese: riprova.", .answerRejected: "La risposta del modello non è utilizzabile: riprova.",
    .improveStale: "Il testo è cambiato nel frattempo: la risposta è stata scartata.",
    .sizeLabel: "Dimensione", .sizeUp: "Più grande", .sizeDown: "Più piccola",
    .send: "Invia a generazione", .noVisibleImage: "Aggiungi almeno un'immagine (con l'occhio acceso).",
    .sendFailed: "Non è stato possibile preparare le immagini.", .noAnswerFromApp: "DT Hub non ha risposto.",
    .pipelineName: "Pano 360 F3", .pipelineReady: "Pronto: premi RUN in DT Hub.",
    .modelNote: "Pronto: i preset sono stati salvati con il modello «%@»: sceglilo nell'intestazione di DT Hub, poi premi RUN.",
    .resultCorrected: "Pano 360 F3 · giunzione corretta", .resultRaw: "Pano 360 F3 · senza correzione della giunzione",
    .runStopped: "Fermato: non è cambiato nulla.", .runClosed: "L'esecuzione è stata chiusa: non è cambiato nulla.",
    .runFailed: "Il passo è fallito: non è cambiato nulla.", .runNoPicture: "DT Hub non ha mandato l'immagine che ha fatto.",
    .runWrongSize: "L'immagine fatta non ha la dimensione del passo (HiRes è acceso nel preset?).",
    .runUnreadable: "L'immagine fatta non si può leggere.", .runDone: "Fatto: il panorama è nei Risultati.",
    .viewerTitle: "Visore", .fixSeam: "Correggi giunzione", .seamNoResult: "Non c'è ancora un risultato da correggere.",
    .seamUnreadable: "Il file dell'immagine non si può leggere.", .seamNotTwoToOne: "L'immagine non è 2:1.",
    .seamSize: "L'altezza dell'immagine non è un multiplo di 64.", .seamTooBig: "L'immagine è troppo alta: il limite è 4096 px.",
    .seamPipelineName: "Pano 360 F3 · giunzione", .seamReady: "Pronto: premi RUN in DT Hub.",
    .noResultYet: "Ancora nessun panorama", .resetView: "Guarda dritto davanti", .dropResult: "Trascina un'immagine per guardarla",
  ]
}
