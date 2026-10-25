import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here.
enum L {
  enum Key: CaseIterable {
    case canvasTitle, guides, clearAll, clearConfirm, clearConfirmMessage, cancel
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
  ]

  private static let it: [Key: String] = [
    .canvasTitle: "Tela 360°", .guides: "Guide", .clearAll: "Cancella tutti gli sticker", .clearConfirm: "Cancella tutti",
    .clearConfirmMessage: "Cancellare tutti gli sticker dalla tela?", .cancel: "Annulla",
  ]
}
