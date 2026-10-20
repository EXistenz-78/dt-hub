import Foundation

/// Le parole del plug-in, in italiano e in inglese. Un bundle contiene solo la libreria, quindi niente file `.strings`:
/// la tabella è qui (i test controllano che le due lingue siano complete).
enum L {
  enum Key: CaseIterable {
    case title
    // Cosa è successo
    case nothingToWrite, writtenCount, failedParts, idsChanged, changedMeanwhile, undone, sent, sentWithConflicts, notAnswered
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
    .title: "Prompt Master F3",
    .nothingToWrite: "Nothing to write yet.", .writtenCount: "%d text(s) written.",
    .failedParts: "Not rewritten (the original stays): %@.", .idsChanged: "the LLM changed the ids of the composition",
    .changedMeanwhile: "Changed while writing, so kept as it is: %@.", .undone: "Previous texts restored.",
    .sent: "Prompt sent.", .sentWithConflicts: "Prompt sent. %d conflict(s) waiting in the app.",
    .notAnswered: "The app did not answer.",
  ]
  private static let it: [Key: String] = [
    .title: "Prompt Master F3",
    .nothingToWrite: "Non c'è ancora niente da scrivere.", .writtenCount: "%d testo/i scritto/i.",
    .failedParts: "Non riscritti (resta l'originale): %@.", .idsChanged: "l'LLM ha cambiato gli id della composizione",
    .changedMeanwhile: "Cambiati mentre scrivevo, restano come sono: %@.", .undone: "Testi precedenti ripristinati.",
    .sent: "Prompt inviato.", .sentWithConflicts: "Prompt inviato. %d conflitto/i in attesa nell'app.",
    .notAnswered: "L'app non ha risposto.",
  ]
}
