import Foundation

/// Le parole del plug-in, in italiano e in inglese. Un bundle contiene solo la libreria, quindi niente file `.strings`:
/// la tabella è qui (i test controllano che le due lingue siano complete).
enum L {
  enum Key: CaseIterable {
    case title
    // Avvisi
    case sizeRatioChanged
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
    .title: "Prompt Master MOSS",
    .sizeRatioChanged:
      "The Generation size changed from %d×%d to %d×%d, a different shape: the boxes keep the same fractions of the canvas, so they are stretched. Check their positions.",
  ]
  private static let it: [Key: String] = [
    .title: "Prompt Master MOSS",
    .sizeRatioChanged:
      "La dimensione della Generazione è passata da %d×%d a %d×%d, con un'altra forma: i box restano nelle stesse frazioni della tela, quindi si deformano. Controlla le posizioni.",
  ]
}
