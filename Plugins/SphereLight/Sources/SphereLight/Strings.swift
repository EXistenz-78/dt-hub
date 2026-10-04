import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here.
enum L {
  enum Key: CaseIterable {
    case lights, preview, light, rotation, elevation, intensity, hardness, color
    case addLight, removeLight
    case overcast, saveDesktop
    case sendPipeline, sendMoodboard
    case sent, sentWithConflicts, savedDesktop, saveFailed
    case noFolder, notAnswered, rendering, renderFailed, active, inactive
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
    .lights: "Lights", .preview: "Preview", .light: "Light %d",
    .rotation: "Rotation (°)", .elevation: "Elevation (°)", .intensity: "Intensity",
    .hardness: "Shadow hardness", .color: "Color",
    .addLight: "Add light", .removeLight: "Remove light",
    .overcast: "Overcast (flatten the shadows first)", .saveDesktop: "Also save to Desktop",
    .sendPipeline: "Send to Generation", .sendMoodboard: "Sphere only, to the Moodboard",
    .sent: "Sent.", .sentWithConflicts: "Sent. %d conflict(s) waiting in the app.",
    .savedDesktop: "Saved to Desktop as %@.", .saveFailed: "Could not save to Desktop.",
    .noFolder: "No picture folder yet: switch the plug-in on first.",
    .notAnswered: "No answer from the app.", .rendering: "Rendering…", .renderFailed: "Rendering failed.",
    .active: "active", .inactive: "not active",
  ]

  private static let it: [Key: String] = [
    .lights: "Luci", .preview: "Anteprima", .light: "Luce %d",
    .rotation: "Rotazione (°)", .elevation: "Elevazione (°)", .intensity: "Intensità",
    .hardness: "Durezza dell'ombra", .color: "Colore",
    .addLight: "Aggiungi una luce", .removeLight: "Togli la luce",
    .overcast: "Overcast (prima appiattisci le ombre)", .saveDesktop: "Salva anche sulla Scrivania",
    .sendPipeline: "Invia a Generazione", .sendMoodboard: "Solo la sfera nel Moodboard",
    .sent: "Inviato.", .sentWithConflicts: "Inviato. %d conflitti in attesa nell'app.",
    .savedDesktop: "Salvata sulla Scrivania come %@.", .saveFailed: "Non si è potuto salvare sulla Scrivania.",
    .noFolder: "La cartella delle immagini non c'è ancora: prima accendi il plug-in.",
    .notAnswered: "Nessuna risposta dall'app.", .rendering: "Calcolo…", .renderFailed: "Calcolo non riuscito.",
    .active: "attivo", .inactive: "non attivo",
  ]
}
