import Foundation

/// Le parole del plug-in, in italiano e in inglese. Un bundle contiene solo la libreria, quindi niente file `.strings`:
/// la tabella è qui (i test controllano che le due lingue siano complete).
enum L {
  enum Key: CaseIterable {
    case title
    // Cosa è successo
    // Le card
    case descriptionTitle, compositionTitle, canvasTitle, elementsTitle, descriptionPlaceholder, photo, art, shuffle
    case compositionPlaceholder, compositionHint, duplicateWarning, generation, canvasHint, elementPlaceholder, position, positionInvalid
    case moveUp, moveDown, removeElement, undo, writeWithLLM, writing, send, sending, noElements, noDescription, clearAll
    case improvedWith, improvedStandard, modePup, modeStandard, pupFailedWith, pupUnusable
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
    .descriptionTitle: "General description", .compositionTitle: "Composition", .canvasTitle: "Canvas", .elementsTitle: "Elements",
    .descriptionPlaceholder: "The whole picture: who or what, doing what, where", .photo: "Photo", .art: "Art", .shuffle: "Shuffle",
    .compositionPlaceholder: "Name the elements with <id> placeholders: a woman <woman_1> next to a red umbrella <umbrella_1>…",
    .compositionHint: "Add an <ID> in the text to create an Element.",
    .duplicateWarning: "%@ appears twice: number the ids (%@_1, %@_2…).", .generation: "Generation",
    .canvasHint: "Drag a box to move it, the corners of the selected one to resize it. New boxes appear from the top left.",
    .elementPlaceholder: "What must appear inside this region", .position: "Position",
    .positionInvalid: "Not a position: four numbers from 0 to 1000, each side at least 20 long.",
    .moveUp: "Move up", .moveDown: "Move down", .removeElement: "Remove this element (and its <id> from the text)",
    .undo: "Undo", .writeWithLLM: "Write with LLM", .writing: "Writing…", .send: "Send", .sending: "Sending…",
    .noElements: "No elements yet.", .noDescription: "(no description)", .clearAll: "Clear",
    .improvedWith: "Improved with %@ (%@).", .improvedStandard: "Improved (%@).", .modePup: "PUP mode", .modeStandard: "standard mode",
    .pupFailedWith: "%@ could not improve the prompt: %@", .pupUnusable: "%@ did not give a usable answer: your texts are unchanged.",
    .nothingToWrite: "Nothing to write yet.", .writtenCount: "%d text(s) written.",
    .failedParts: "Not rewritten (the original stays): %@.", .idsChanged: "the LLM changed the ids of the composition",
    .changedMeanwhile: "Changed while writing, so kept as it is: %@.", .undone: "Previous texts restored.",
    .sent: "Prompt sent.", .sentWithConflicts: "Prompt sent. %d conflict(s) waiting in the app.",
    .notAnswered: "The app did not answer.",
  ]
  private static let it: [Key: String] = [
    .title: "Prompt Master F3",
    .descriptionTitle: "Descrizione generale", .compositionTitle: "Composizione", .canvasTitle: "Canvas", .elementsTitle: "Elementi",
    .descriptionPlaceholder: "L'immagine intera: chi o che cosa, che cosa fa, dove", .photo: "Foto", .art: "Arte", .shuffle: "Shuffle",
    .compositionPlaceholder: "Nomina gli elementi con segnaposto <id>: una donna <woman_1> accanto a un ombrello rosso <umbrella_1>…",
    .compositionHint: "Aggiungi un <ID> nel testo per creare un Elemento.",
    .duplicateWarning: "%@ compare due volte: numera gli id (%@_1, %@_2…).", .generation: "Generazione",
    .canvasHint: "Trascina un box per spostarlo, gli angoli di quello selezionato per ridimensionarlo. I box nuovi compaiono dall'alto a sinistra.",
    .elementPlaceholder: "Che cosa deve apparire in questa regione", .position: "Posizione",
    .positionInvalid: "Non è una posizione: quattro numeri da 0 a 1000, ogni lato lungo almeno 20.",
    .moveUp: "Sposta su", .moveDown: "Sposta giù", .removeElement: "Rimuovi questo elemento (e il suo <id> dal testo)",
    .undo: "Annulla", .writeWithLLM: "Scrivi con LLM", .writing: "Scrivo…", .send: "Invia", .sending: "Invio…",
    .noElements: "Ancora nessun elemento.", .noDescription: "(senza descrizione)", .clearAll: "Svuota",
    .improvedWith: "Migliorato con %@ (%@).", .improvedStandard: "Migliorato (%@).", .modePup: "modalità PUP", .modeStandard: "modalità standard",
    .pupFailedWith: "%@ non è riuscito a migliorare il prompt: %@", .pupUnusable: "%@ non ha dato una risposta utilizzabile: i tuoi testi restano come erano.",
    .nothingToWrite: "Non c'è ancora niente da scrivere.", .writtenCount: "%d testo/i scritto/i.",
    .failedParts: "Non riscritti (resta l'originale): %@.", .idsChanged: "l'LLM ha cambiato gli id della composizione",
    .changedMeanwhile: "Cambiati mentre scrivevo, restano come sono: %@.", .undone: "Testi precedenti ripristinati.",
    .sent: "Prompt inviato.", .sentWithConflicts: "Prompt inviato. %d conflitto/i in attesa nell'app.",
    .notAnswered: "L'app non ha risposto.",
  ]
}
