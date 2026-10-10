import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no `.strings`
/// files: the table is here. (The titles of the cards and the sentences are not here: they are the prompt, always English.)
enum L {
  enum Key: CaseIterable {
    case toolSketch, toolBox, toolCircle, toolArrow
    case cYellow, cRed, cBlue, cCyan, cMagenta, cGreen, cPurple, cWhite, cBlack
    case clearAll, clearConfirm, undo, redo, width, cancel
    case noImage, notActive, previewTitle, previewEmpty, usePE
    case send, sending, enhancing, sent, sentConflicts, notAnswered, peFallback, peNoReason
    case cardPlaceholder
  }

  static var systemIsItalian: Bool {
    Locale.preferredLanguages.first?.hasPrefix("it") ?? false
  }

  static func text(_ key: Key, italian: Bool = systemIsItalian) -> String {
    (italian ? it : en)[key] ?? en[key] ?? "\(key)"
  }

  /// Whether the word is in the table of that language (the tests check both are complete).
  static func isDefined(_ key: Key, italian: Bool) -> Bool {
    (italian ? it : en)[key] != nil
  }

  static func format(_ key: Key, _ args: CVarArg..., italian: Bool = systemIsItalian) -> String {
    String(format: text(key, italian: italian), arguments: args)
  }

  private static let en: [Key: String] = [
    .toolSketch: "Brush", .toolBox: "Rectangle", .toolCircle: "Oval", .toolArrow: "Arrow",
    .cYellow: "Yellow", .cRed: "Red", .cBlue: "Blue", .cCyan: "Cyan", .cMagenta: "Magenta", .cGreen: "Green",
    .cPurple: "Purple", .cWhite: "White", .cBlack: "Black",
    .clearAll: "Clear all", .clearConfirm: "Remove all the marks?", .undo: "Undo", .redo: "Redo", .width: "Width",
    .cancel: "Cancel",
    .noImage: "Put a start image in Control.", .notActive: "Switch Qwen 2.1 Inpainting on from the plug-ins menu.",
    .previewTitle: "Prompt", .previewEmpty: "Write what to change in the cards: the prompt appears here.",
    .usePE: "Improve with %@",
    .send: "Send", .sending: "Sending…", .enhancing: "Enhancer working…", .sent: "Sent.",
    .sentConflicts: "Sent. %d conflict(s) waiting in the app.", .notAnswered: "No answer from the app.",
    .peFallback: "Enhancer not available: the direct prompt was sent (%@)", .peNoReason: "no answer",
    .cardPlaceholder: "What to change here",
  ]

  private static let it: [Key: String] = [
    .toolSketch: "Pennello", .toolBox: "Rettangolo", .toolCircle: "Ovale", .toolArrow: "Freccia",
    .cYellow: "Giallo", .cRed: "Rosso", .cBlue: "Blu", .cCyan: "Ciano", .cMagenta: "Magenta", .cGreen: "Verde",
    .cPurple: "Viola", .cWhite: "Bianco", .cBlack: "Nero",
    .clearAll: "Cancella tutto", .clearConfirm: "Togliere tutti i segni?", .undo: "Annulla", .redo: "Ripeti", .width: "Spessore",
    .cancel: "Annulla",
    .noImage: "Metti un'immagine di partenza in Control.", .notActive: "Accendi Qwen 2.1 Inpainting dal menu dei plug-in.",
    .previewTitle: "Prompt", .previewEmpty: "Scrivi cosa cambiare nelle card: qui compare il prompt.",
    .usePE: "Migliora con %@",
    .send: "Invia", .sending: "Invio…", .enhancing: "PE in corso…", .sent: "Inviato.",
    .sentConflicts: "Inviato. %d conflitti in attesa nell'app.", .notAnswered: "Nessuna risposta dall'app.",
    .peFallback: "PE non disponibile: inviato il prompt diretto (%@)", .peNoReason: "nessuna risposta",
    .cardPlaceholder: "Cosa cambiare qui",
  ]
}
