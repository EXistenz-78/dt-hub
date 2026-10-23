import Foundation

/// Le parole del plug-in, in italiano e in inglese. Un bundle contiene solo la libreria, quindi niente file `.strings`:
/// la tabella è qui (i test controllano che le due lingue siano complete).
enum L {
  enum Key: CaseIterable {
    case title
    // Avvisi
    case sizeRatioChanged, reviewDiscarded
    // Canvas
    case canvas, generation, labelObject, labelCharacter, labelText, labelPanel, labelSubject
    // Interfaccia
    case summaryTitle, descriptionLabel, descriptionPlaceholder, photo, art, shuffle, metaTitle, metaPlaceholder, canvasKind
    case paletteTitle, negativeTitle, negativePlaceholder, elementsTitle, noElements, captionLabel, textLabel, verbatim, tagsLabel
    case position, positionInvalid, colorsLabel, moveUp, moveDown, removeElement, noCaption, addColor, removeColor
    case undo, writeWithLLM, writing, reviewJSON, send, sending, copy, restoreFromFields, close, reviewNote
    case sent, sentWithConflicts, notAnswered, captionPlaceholder, textPlaceholder
    // Perché «Invia» è disattivato
    case problemUnknownSize, problemEmptySummary, problemNoItems, problemEmptyCaption, problemEmptyText
    // Scrittura con l'LLM
    case nothingToWrite, writtenCount, failedParts, changedMeanwhile, undone
  }

  static var systemIsItalian: Bool {
    Locale.preferredLanguages.first?.hasPrefix("it") ?? false
  }

  static func text(_ key: Key, italian: Bool = systemIsItalian) -> String {
    (italian ? it : en)[key] ?? en[key] ?? "\(key)"
  }

  /// Il nome di un tipo di elemento.
  static func name(of label: MossLabel, italian: Bool = systemIsItalian) -> String {
    switch label {
    case .object: return text(.labelObject, italian: italian)
    case .character: return text(.labelCharacter, italian: italian)
    case .text: return text(.labelText, italian: italian)
    case .panel: return text(.labelPanel, italian: italian)
    case .subject: return text(.labelSubject, italian: italian)
    }
  }

  static func isDefined(_ key: Key, italian: Bool) -> Bool { (italian ? it : en)[key] != nil }

  static func format(_ key: Key, _ args: CVarArg..., italian: Bool = systemIsItalian) -> String {
    String(format: text(key, italian: italian), arguments: args)
  }

  private static let en: [Key: String] = [
    .title: "Prompt Master MOSS",
    .sizeRatioChanged:
      "The Generation size changed from %d×%d to %d×%d, a different shape: the boxes keep the same fractions of the canvas, so they are stretched. Check their positions.",
    .summaryTitle: "MOSS Image · Summary", .descriptionLabel: "General description",
    .descriptionPlaceholder: "The whole picture: who or what, doing what, where", .photo: "Photo", .art: "Art", .shuffle: "Shuffle",
    .metaTitle: "Meta", .metaPlaceholder: "Add a free tag and press Return", .canvasKind: "Canvas", .paletteTitle: "Color palette",
    .negativePlaceholder: "Other negative terms, separated by commas", .negativeTitle: "Negative",
    .elementsTitle: "Elements", .noElements: "No elements yet: drag on the canvas to make one.", .captionLabel: "Caption",
    .textLabel: "Text", .verbatim: "verbatim", .tagsLabel: "Tags", .position: "Position",
    .positionInvalid: "Not a position: four numbers, y0, x0, y1, x1, from the center.", .colorsLabel: "Colors",
    .moveUp: "Move up", .moveDown: "Move down", .removeElement: "Remove this element", .noCaption: "(no caption)",
    .addColor: "Add a color", .removeColor: "Remove this color", .undo: "Undo", .writeWithLLM: "Write with LLM", .writing: "Writing…",
    .reviewJSON: "Review JSON", .send: "Send", .sending: "Sending…", .copy: "Copy", .restoreFromFields: "Restore from fields",
    .close: "Close", .reviewNote: "Edited by hand: \"Send\" sends this text. The fields do not update it until you restore it.",
    .sent: "Prompt sent.", .sentWithConflicts: "Prompt sent. %d conflict(s) waiting in the app.", .notAnswered: "The app did not answer.",
    .captionPlaceholder: "What this region looks like", .textPlaceholder: "The exact text, line breaks with Return",
    .problemUnknownSize: "The Generation size is not known yet, or it is not a multiple of 16.",
    .problemEmptySummary: "Write the general description (or pick terms).", .problemNoItems: "Draw at least one element on the canvas.",
    .problemEmptyCaption: "Element %d has no caption.", .problemEmptyText: "Element %d is a Text with no text.",
    .canvas: "Canvas", .generation: "Generation", .labelObject: "Object", .labelCharacter: "Character", .labelText: "Text",
    .labelPanel: "Panel", .labelSubject: "Subject",
    .reviewDiscarded: "The Generation size changed, so the JSON you edited by hand was discarded (its coordinates were for the old size).",
    .nothingToWrite: "Nothing to write yet.", .writtenCount: "%d text(s) written.",
    .failedParts: "Not rewritten (the original stays): %@.", .changedMeanwhile: "Changed while writing, so kept as it is: %@.",
    .undone: "Previous texts restored.",
  ]
  private static let it: [Key: String] = [
    .title: "Prompt Master MOSS",
    .sizeRatioChanged:
      "La dimensione della Generazione è passata da %d×%d a %d×%d, con un'altra forma: i box restano nelle stesse frazioni della tela, quindi si deformano. Controlla le posizioni.",
    .summaryTitle: "MOSS Image · Summary", .descriptionLabel: "Descrizione generale",
    .descriptionPlaceholder: "Tutta l'immagine: chi o cosa, che cosa fa, dove", .photo: "Foto", .art: "Arte", .shuffle: "Shuffle",
    .metaTitle: "Meta", .metaPlaceholder: "Aggiungi un tag libero e premi Invio", .canvasKind: "Canvas", .paletteTitle: "Palette colori",
    .negativePlaceholder: "Altri termini del negativo, separati da virgola", .negativeTitle: "Negativo",
    .elementsTitle: "Elementi", .noElements: "Nessun elemento: trascina sul canvas per crearne uno.", .captionLabel: "Caption",
    .textLabel: "Testo", .verbatim: "verbatim", .tagsLabel: "Tags", .position: "Posizione",
    .positionInvalid: "Non è una posizione: quattro numeri, y0, x0, y1, x1, dal centro.", .colorsLabel: "Colori",
    .moveUp: "Sposta su", .moveDown: "Sposta giù", .removeElement: "Elimina questo elemento", .noCaption: "(nessuna caption)",
    .addColor: "Aggiungi un colore", .removeColor: "Togli questo colore", .undo: "Annulla", .writeWithLLM: "Scrivi con LLM",
    .writing: "Scrivo…", .reviewJSON: "Rivedi JSON", .send: "Invia", .sending: "Invio…", .copy: "Copia",
    .restoreFromFields: "Ripristina dai campi", .close: "Chiudi",
    .reviewNote: "Modificato a mano: «Invia» manda questo testo. I campi non lo aggiornano finché non lo ripristini.",
    .sent: "Prompt inviato.", .sentWithConflicts: "Prompt inviato. %d conflitto/i in attesa nell'app.", .notAnswered: "L'app non ha risposto.",
    .captionPlaceholder: "Che aspetto ha questa zona", .textPlaceholder: "Il testo esatto, a capo con Invio",
    .problemUnknownSize: "La dimensione della Generazione non è ancora nota, o non è un multiplo di 16.",
    .problemEmptySummary: "Scrivi la descrizione generale (o scegli dei termini).", .problemNoItems: "Disegna almeno un elemento sul canvas.",
    .problemEmptyCaption: "L'elemento %d non ha la caption.", .problemEmptyText: "L'elemento %d è un Testo senza testo.",
    .canvas: "Canvas", .generation: "Generazione", .labelObject: "Oggetto", .labelCharacter: "Personaggio", .labelText: "Testo",
    .labelPanel: "Pannello", .labelSubject: "Soggetto",
    .reviewDiscarded: "La dimensione della Generazione è cambiata, quindi il JSON modificato a mano è stato scartato (le sue coordinate erano per la dimensione di prima).",
    .nothingToWrite: "Niente da scrivere.", .writtenCount: "%d testi scritti.",
    .failedParts: "Non riscritti (resta l'originale): %@.", .changedMeanwhile: "Cambiati mentre scrivevo, quindi restano come sono: %@.",
    .undone: "Testi precedenti ripristinati.",
  ]
}
