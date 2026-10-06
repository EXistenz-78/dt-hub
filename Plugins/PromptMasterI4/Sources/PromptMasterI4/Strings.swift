import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here (the tests check both languages are complete).
enum L {
  enum Key: CaseIterable {
    // The list
    case title, description, descriptionPlaceholder, photo, art, shuffle, aesthetics, lighting, photoStyle, artStyle, medium
    case none, palette, addColor, removeColor, background, backgroundPlaceholder
    // The elements
    case elements, addObject, addText, objectPlaceholder, textPlaceholder, lettering, printedText
    case printedTextPlaceholder, position, noPosition, positionPlaceholder, moveUp, moveDown, removeElement
    case noDescription, emptyText
    // The canvas
    case canvas, generation, canvasHint
    // The JSON
    case reviewJSON, jsonEdited, restore, copy, close, send, sending
    // What happened
    case sent, sentWithConflicts, notAnswered, missingCategory
    case unreadableFile, unknownSchema, repeatedIDs
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
    .title: "Ideogram 4", .description: "High level description",
    .descriptionPlaceholder: "The whole picture: who or what, doing what, where", .photo: "Photo", .art: "Art",
    .shuffle: "Shuffle", .aesthetics: "Aesthetics", .lighting: "Lighting", .photoStyle: "Photo", .artStyle: "Art style",
    .medium: "Medium", .none: "—", .palette: "Color palette", .addColor: "Add a color", .removeColor: "Remove this color",
    .background: "Background", .backgroundPlaceholder: "What is behind everything else",
    .elements: "Elements", .addObject: "Add an object", .addText: "Add a text",
    .objectPlaceholder: "Describe the object", .textPlaceholder: "How the lettering looks, not what it says",
    .lettering: "Text & Lettering", .printedText: "Text (rendered as written)", .printedTextPlaceholder: "The words in the picture",
    .position: "Position", .noPosition: "no position", .positionPlaceholder: "y0, x0, y1, x1 (0–1000, sides of at least 20)",
    .moveUp: "Move up", .moveDown: "Move down", .removeElement: "Remove this element",
    .noDescription: "(no description)", .emptyText: "(no text)",
    .canvas: "Canvas", .generation: "Generation",
    .canvasHint: "Drag on empty canvas to make an object; drag a box to move it, its corners to resize it. Click the tag of a selected box to turn it into text, or back into an object.",
    .reviewJSON: "Review JSON", .jsonEdited: "JSON edited by hand", .restore: "Restore from the fields", .copy: "Copy",
    .close: "Close", .send: "Send", .sending: "Sending…",
    .sent: "Caption sent to Generation.", .sentWithConflicts: "Caption sent. %d conflict(s) waiting in the app.",
    .notAnswered: "No answer from the app.",
    .missingCategory: "The category “%@” is not in the database: that list is shorter.",
    .unreadableFile: "%@ cannot be read: using the copy built into the plug-in.",
    .unknownSchema: "%@ has a layout this plug-in does not know: using the copy built into the plug-in.",
    .repeatedIDs: "%@ uses the same id twice: using the copy built into the plug-in.",
  ]

  private static let it: [Key: String] = [
    .title: "Ideogram 4", .description: "High level description",
    .descriptionPlaceholder: "L'immagine intera: chi o che cosa, che cosa fa, dove", .photo: "Foto", .art: "Arte",
    .shuffle: "Shuffle", .aesthetics: "Aesthetics", .lighting: "Lighting", .photoStyle: "Photo", .artStyle: "Art style",
    .medium: "Medium", .none: "—", .palette: "Palette colori", .addColor: "Aggiungi un colore", .removeColor: "Togli questo colore",
    .background: "Background", .backgroundPlaceholder: "Che cosa c'è dietro a tutto il resto",
    .elements: "Elementi", .addObject: "Aggiungi oggetto", .addText: "Aggiungi testo",
    .objectPlaceholder: "Descrivi l'oggetto", .textPlaceholder: "Com'è la scritta, non che cosa dice",
    .lettering: "Text & Lettering", .printedText: "Testo (reso verbatim)", .printedTextPlaceholder: "Le parole che compaiono nell'immagine",
    .position: "Posizione", .noPosition: "nessuna posizione", .positionPlaceholder: "y0, x0, y1, x1 (0–1000, lati di almeno 20)",
    .moveUp: "Sposta su", .moveDown: "Sposta giù", .removeElement: "Togli questo elemento",
    .noDescription: "(nessuna descrizione)", .emptyText: "(testo vuoto)",
    .canvas: "Canvas", .generation: "Generazione",
    .canvasHint: "Trascina sul vuoto per fare un oggetto; trascina un riquadro per spostarlo, gli angoli per ridimensionarlo. Clic sull'etichetta di un riquadro selezionato per farlo diventare testo, o di nuovo oggetto.",
    .reviewJSON: "Rivedi JSON", .jsonEdited: "JSON modificato a mano", .restore: "Ripristina dai campi", .copy: "Copia",
    .close: "Chiudi", .send: "Invia", .sending: "Invio…",
    .sent: "Didascalia inviata alla Generazione.", .sentWithConflicts: "Didascalia inviata. %d conflitti in attesa nell'app.",
    .notAnswered: "Nessuna risposta dall'app.",
    .missingCategory: "La categoria «%@» non è nel database: quell'elenco è più corto.",
    .unreadableFile: "%@ non si legge: uso la copia incorporata nel plug-in.",
    .unknownSchema: "%@ ha un formato che questo plug-in non conosce: uso la copia incorporata.",
    .repeatedIDs: "%@ usa lo stesso id due volte: uso la copia incorporata nel plug-in.",
  ]
}
