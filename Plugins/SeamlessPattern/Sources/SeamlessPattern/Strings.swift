import Foundation

/// The words of the tab, in Italian and English. A plug-in bundle holds only its library, so there are no `.strings`
/// files: the table is here. The texts an agent reads through the tools stay in English (`agent…`).
enum L {
  enum Key: CaseIterable {
    case title, repeatTitle, both, leftRight, upDown, prepare, stop, prepared
    case lastResult, noImage, view, seam, tile, offset
    case needsServer, unsupportedFamily
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

  // MARK: For agents (English, like every tool text)

  static let agentNeedsServer =
    "Seamless Pattern needs DT Hub's own server (Preferences › Draw Things: use the included server)."
  static let agentUnsupportedFamily = "This model family is not supported."
  static let notAnswered = "No answer from the app."

  static func mode(_ mode: SPMode, italian: Bool = systemIsItalian) -> String {
    switch mode {
    case .both: text(.both, italian: italian)
    case .leftRight: text(.leftRight, italian: italian)
    case .upDown: text(.upDown, italian: italian)
    }
  }

  static func view(_ view: SPView, italian: Bool = systemIsItalian) -> String {
    switch view {
    case .tile: text(.tile, italian: italian)
    case .twoByTwo: "2×2"
    case .threeByThree: "3×3"
    case .offset: text(.offset, italian: italian)
    }
  }

  private static let en: [Key: String] = [
    .title: "Seamless Pattern", .repeatTitle: "Repeat", .both: "Both", .leftRight: "Left-right", .upDown: "Up-down",
    .prepare: "Prepare Run · Seamless", .stop: "Stop seamless",
    .prepared: "Ready: press Run (it says “Run · Seamless”).",
    .lastResult: "Last result", .noImage: "No picture yet. Run, or drop an image here.",
    .view: "View", .seam: "Seam", .tile: "Tile", .offset: "Offset",
    .needsServer: agentNeedsServer, .unsupportedFamily: agentUnsupportedFamily,
  ]

  private static let it: [Key: String] = [
    .title: "Seamless Pattern", .repeatTitle: "Ripeti", .both: "Entrambi", .leftRight: "Sinistra-destra",
    .upDown: "Su-giù",
    .prepare: "Prepara Run · Seamless", .stop: "Ferma seamless",
    .prepared: "Pronto: premi Run (dice «Run · Seamless»).",
    .lastResult: "Ultimo risultato", .noImage: "Ancora nessuna immagine. Premi Run, o trascina qui un'immagine.",
    .view: "Vista", .seam: "Giunzione", .tile: "Tile", .offset: "Sfalsata",
    .needsServer: "Seamless Pattern ha bisogno del server di DT Hub (Preferenze › Draw Things: usa il server incluso in DT Hub).",
    .unsupportedFamily: "Questa famiglia di modelli non è supportata.",
  ]
}
