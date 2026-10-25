import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here.
enum L {
  enum Key: CaseIterable {
    case canvasTitle, guides, clearAll, clearConfirm, clearConfirmMessage, cancel
    case stickersTitle, yaw, pitch, rotation, fieldOfView, verticalFieldOfView, opacity, duplicate, delete, add, toggleVisible
    case croppedPhoto, unreadableFile, openProjectFirst, dropHere
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
