import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here.
enum L {
  enum Key: CaseIterable {
    case dropHere, open, image, mode, depth, pose, mapsPlaceholder
    case create, sendToMoodboard, downloadModel, redownload, cancel, downloading
    case depthMissing, creating, created, sent, sentWithConflicts, sentWithProblems
    case noFolder, notAnswered, unreadableImage, noPerson, poseOnlyBecauseNoModel
    case downloadFailed, modelDamaged, noMapsToSend, writeFailed, saveToDesktop, savedDesktop, saveFailed
    case active, inactive
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
    .dropHere: "Drop an image here", .open: "Open…", .image: "Image", .mode: "Maps",
    .mapsPlaceholder: "The maps appear here.",
    .depth: "Depth", .pose: "Pose",
    .create: "Create", .sendToMoodboard: "Send to the Moodboard",
    .downloadModel: "Download the model (50 MB)", .redownload: "Download the model again", .cancel: "Cancel",
    .downloading: "Downloading… %d%%",
    .depthMissing: "The depth model is not on this Mac yet: download it first.",
    .creating: "Working…", .created: "Done.",
    .sent: "Sent.", .sentWithConflicts: "Sent. %d conflict(s) waiting in the app.",
    .sentWithProblems: "Sent. The app says: %@",
    .noFolder: "No picture folder yet: switch the plug-in on first.",
    .notAnswered: "No answer from the app.",
    .unreadableImage: "This image could not be read.",
    .noPerson: "No person found in the image: no pose.",
    .poseOnlyBecauseNoModel: "The depth model is missing: only the pose was created.",
    .downloadFailed: "The download failed: %@",
    .modelDamaged: "The depth model on disk does not open: download it again.",
    .noMapsToSend: "Nothing to send yet: press Create first.",
    .writeFailed: "The pictures could not be written to the picture folder.",
    .saveToDesktop: "Save to Desktop", .savedDesktop: "Saved to Desktop as %@.",
    .saveFailed: "Could not save to Desktop.",
    .active: "active", .inactive: "not active",
  ]

  private static let it: [Key: String] = [
    .dropHere: "Trascina qui un'immagine", .open: "Apri…", .image: "Immagine", .mode: "Mappe",
    .mapsPlaceholder: "Le mappe compaiono qui.",
    .depth: "Depth", .pose: "Posa",
    .create: "Crea", .sendToMoodboard: "Manda al Moodboard",
    .downloadModel: "Scarica il modello (50 MB)", .redownload: "Scarica di nuovo il modello", .cancel: "Annulla",
    .downloading: "Scarico… %d%%",
    .depthMissing: "Il modello della depth non è ancora su questo Mac: prima scaricalo.",
    .creating: "Calcolo…", .created: "Fatto.",
    .sent: "Inviato.", .sentWithConflicts: "Inviato. %d conflitti in attesa nell'app.",
    .sentWithProblems: "Inviato. L'app dice: %@",
    .noFolder: "La cartella delle immagini non c'è ancora: prima accendi il plug-in.",
    .notAnswered: "Nessuna risposta dall'app.",
    .unreadableImage: "Non si è potuta leggere questa immagine.",
    .noPerson: "Nessuna persona trovata nell'immagine: niente posa.",
    .poseOnlyBecauseNoModel: "Manca il modello della depth: è stata creata solo la posa.",
    .downloadFailed: "Il download non è riuscito: %@",
    .modelDamaged: "Il modello della depth su disco non si apre: scaricalo di nuovo.",
    .noMapsToSend: "Non c'è ancora niente da mandare: prima premi Crea.",
    .writeFailed: "Non si sono potute scrivere le immagini nella cartella delle immagini.",
    .saveToDesktop: "Salva sulla Scrivania", .savedDesktop: "Salvate sulla Scrivania come %@.",
    .saveFailed: "Non si è potuto salvare sulla Scrivania.",
    .active: "attivo", .inactive: "non attivo",
  ]
}
