import Foundation

/// Le parole del plug-in, in italiano e in inglese. Un bundle contiene solo la libreria, quindi niente file `.strings`:
/// la tabella è qui (i test controllano che le due lingue siano complete).
enum L {
  enum Key: CaseIterable {
    case title
    case noWindow, undone
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
  ]
  private static let it: [Key: String] = [
    .title: "Flux3 Editing",
    .noWindow: "Questa app non dice dove sta l'immagine nel canvas: la vedi intera adattata, quindi i riquadri possono non corrispondere se è ingrandita o ha dei margini.",
    .undone: "Testi precedenti ripristinati.",
  ]
}
