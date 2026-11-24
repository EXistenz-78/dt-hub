import Foundation

/// Le parole del plug-in, in italiano e in inglese. Un bundle contiene solo la libreria, quindi niente file `.strings`:
/// la tabella è qui (i test controllano che le due lingue siano complete).
enum L {
  enum Key: CaseIterable {
    case title
    // Avvisi
    case sizeRatioChanged
    // Canvas
    case canvas, generation, labelObject, labelText
    // Interfaccia
    case settingsTitle, ideaLabel, ideaPlaceholder, photo, art, shuffle, imageStyleLabel, imageStylePlaceholder
    case ambientLightingLabel, ambientLightingPlaceholder, layersTitle, noLayers
    case descriptionLabel, objectPlaceholder, lookLabel, lookPlaceholder, textLabel, verbatim, textPlaceholder
    case relationLabel, relationPlaceholder, position, positionInvalid, colorsLabel, moveUp, moveDown, removeLayer, noDescription
    case addColor, removeColor, undo, writeWithLLM, composeWithLLM, writing, send, sending, clearAll, backFront
    case sent, sentWithConflicts, notAnswered
    // Importa
    case importFromGeneration, importOffer, importNow, importDismiss, importedCount, importFailed, importNoPrompt
    case sourceGeneration, sizeChangedForImport, sizeNotChanged
    // Perché «Invia» è disattivato
    case problemUnknownSize, problemNoLayers, problemEmptyDescription, problemEmptyText
    // Scrittura con l'LLM
    case nothingToWrite, writtenCount, failedParts, changedMeanwhile, undone, cleared, composedCount, composeFailed, composeNeedsIdea
  }

  static var systemIsItalian: Bool {
    Locale.preferredLanguages.first?.hasPrefix("it") ?? false
  }

  static func text(_ key: Key, italian: Bool = systemIsItalian) -> String {
    (italian ? it : en)[key] ?? en[key] ?? "\(key)"
  }

  /// Il nome di un tipo di livello.
  static func name(of kind: MingKind, italian: Bool = systemIsItalian) -> String {
    switch kind {
    case .object: return text(.labelObject, italian: italian)
    case .text: return text(.labelText, italian: italian)
    }
  }

  static func isDefined(_ key: Key, italian: Bool) -> Bool { (italian ? it : en)[key] != nil }

  static func format(_ key: Key, _ args: CVarArg..., italian: Bool = systemIsItalian) -> String {
    String(format: text(key, italian: italian), arguments: args)
  }

  private static let en: [Key: String] = [
    .title: "Prompt Master Ming",
    .sizeRatioChanged:
      "The Generation size changed from %d×%d to %d×%d, a different shape: the boxes keep the same fractions of the canvas, so they are stretched. Check their positions.",
    .settingsTitle: "Ming-Image · Canvas settings", .ideaLabel: "Idea (for Compose)",
    .ideaPlaceholder: "The design in your own words, in any language: what it is, the texts it shows, the style",
    .photo: "Photo", .art: "Art", .shuffle: "Shuffle", .imageStyleLabel: "Image Style",
    .imageStylePlaceholder: "The style or medium of the whole picture", .ambientLightingLabel: "Ambient Lighting",
    .ambientLightingPlaceholder: "The light of the whole picture",
    .layersTitle: "Layers", .noLayers: "No layers yet: drag on the canvas to make one, import a JSON or compose with the LLM.",
    .descriptionLabel: "Description", .objectPlaceholder: "What this layer is: material, colors, what sits where inside it",
    .lookLabel: "Look of the lettering", .lookPlaceholder: "Font, weight, color, effects (without the words)",
    .textLabel: "Exact text", .verbatim: "verbatim", .textPlaceholder: "The exact words, line breaks with Return",
    .relationLabel: "Hierarchy and relation", .relationPlaceholder: "How it sits with the others: above the title, inside the card…",
    .position: "Coordinates", .positionInvalid: "Not a position: cx, cy, w, h as fractions from 0 to 1.", .colorsLabel: "Colors",
    .moveUp: "Toward the back", .moveDown: "Toward the front", .removeLayer: "Remove this layer", .noDescription: "(no description)",
    .addColor: "Add a color", .removeColor: "Remove this color", .undo: "Undo", .writeWithLLM: "Write with LLM",
    .composeWithLLM: "Compose with LLM", .writing: "Writing…", .send: "Send", .sending: "Sending…", .clearAll: "Clear all",
    .backFront: "L1 is the background, the last layer is in front.",
    .sent: "Prompt sent.", .sentWithConflicts: "Prompt sent. %d conflict(s) waiting in the app.", .notAnswered: "The app did not answer.",
    .importFromGeneration: "Import from Generation",
    .importOffer: "The Generation prompt is a Ming JSON: import it as layers?", .importNow: "Import", .importDismiss: "Ignore",
    .importedCount: "%d layer(s) imported from %@.", .importFailed: "Not a Ming JSON (%@): nothing changed.",
    .importNoPrompt: "The Generation prompt is empty.", .sourceGeneration: "the Generation prompt",
    .sizeChangedForImport: "Generation size set to %d×%d for the JSON's aspect ratio.",
    .sizeNotChanged: "The JSON asks for %d×%d: set it in the Generation tab.",
    .problemUnknownSize: "The Generation size is not known yet.", .problemNoLayers: "Draw at least one layer on the canvas.",
    .problemEmptyDescription: "Layer %d has no description.", .problemEmptyText: "Layer %d is a Text with no words.",
    .canvas: "Canvas", .generation: "Generation", .labelObject: "Object", .labelText: "Text",
    .nothingToWrite: "Nothing to write yet.", .writtenCount: "%d text(s) written.",
    .failedParts: "Not rewritten (the original stays): %@.", .changedMeanwhile: "Changed while writing, so kept as it is: %@.",
    .undone: "Previous state restored.", .cleared: "Layers and settings cleared (Undo brings them back).",
    .composedCount: "Layout composed: %d layer(s).", .composeFailed: "The LLM's layout could not be read (%@): nothing changed.",
    .composeNeedsIdea: "Write the idea first.",
  ]
  private static let it: [Key: String] = [
    .title: "Prompt Master Ming",
    .sizeRatioChanged:
      "La dimensione della Generazione è passata da %d×%d a %d×%d, con un'altra forma: i box restano nelle stesse frazioni della tela, quindi si deformano. Controlla le posizioni.",
    .settingsTitle: "Ming-Image · Impostazioni della tela", .ideaLabel: "Idea (per Componi)",
    .ideaPlaceholder: "Il design con parole tue, in qualsiasi lingua: che cos'è, i testi che mostra, lo stile",
    .photo: "Foto", .art: "Arte", .shuffle: "Shuffle", .imageStyleLabel: "Image Style",
    .imageStylePlaceholder: "Lo stile o il medium di tutta l'immagine", .ambientLightingLabel: "Ambient Lighting",
    .ambientLightingPlaceholder: "La luce di tutta l'immagine",
    .layersTitle: "Livelli", .noLayers: "Nessun livello: trascina sul canvas per crearne uno, importa un JSON o componi con l'LLM.",
    .descriptionLabel: "Descrizione", .objectPlaceholder: "Che cos'è questo livello: materiale, colori, cosa c'è dentro e dove",
    .lookLabel: "Aspetto delle lettere", .lookPlaceholder: "Carattere, peso, colore, effetti (senza le parole)",
    .textLabel: "Testo esatto", .verbatim: "verbatim", .textPlaceholder: "Le parole esatte, a capo con Invio",
    .relationLabel: "Gerarchia e relazione", .relationPlaceholder: "Come sta con gli altri: sopra il titolo, dentro la card…",
    .position: "Coordinate", .positionInvalid: "Non è una posizione: cx, cy, w, h in frazioni da 0 a 1.", .colorsLabel: "Colori",
    .moveUp: "Verso il fondo", .moveDown: "Verso il primo piano", .removeLayer: "Elimina questo livello",
    .noDescription: "(nessuna descrizione)", .addColor: "Aggiungi un colore", .removeColor: "Togli questo colore", .undo: "Annulla",
    .writeWithLLM: "Scrivi con LLM", .composeWithLLM: "Componi con LLM", .writing: "Scrivo…", .send: "Invia", .sending: "Invio…",
    .clearAll: "Svuota", .backFront: "L1 è lo sfondo, l'ultimo livello sta davanti.",
    .sent: "Prompt inviato.", .sentWithConflicts: "Prompt inviato. %d conflitto/i in attesa nell'app.", .notAnswered: "L'app non ha risposto.",
    .importFromGeneration: "Importa dalla Generazione",
    .importOffer: "Il prompt della Generazione è un JSON Ming: importarlo come livelli?", .importNow: "Importa",
    .importDismiss: "Ignora", .importedCount: "%d livelli importati da %@.", .importFailed: "Non è un JSON Ming (%@): nulla è cambiato.",
    .importNoPrompt: "Il prompt della Generazione è vuoto.", .sourceGeneration: "il prompt della Generazione",
    .sizeChangedForImport: "Dimensione della Generazione impostata a %d×%d per il rapporto del JSON.",
    .sizeNotChanged: "Il JSON chiede %d×%d: impostala nella tab Generazione.",
    .problemUnknownSize: "La dimensione della Generazione non è ancora nota.", .problemNoLayers: "Disegna almeno un livello sul canvas.",
    .problemEmptyDescription: "Il livello %d non ha la descrizione.", .problemEmptyText: "Il livello %d è un Testo senza parole.",
    .canvas: "Canvas", .generation: "Generazione", .labelObject: "Oggetto", .labelText: "Testo",
    .nothingToWrite: "Niente da scrivere.", .writtenCount: "%d testi scritti.",
    .failedParts: "Non riscritti (resta l'originale): %@.", .changedMeanwhile: "Cambiati mentre scrivevo, quindi restano come sono: %@.",
    .undone: "Stato precedente ripristinato.", .cleared: "Livelli e impostazioni svuotati (Annulla li rimette).",
    .composedCount: "Layout composto: %d livelli.", .composeFailed: "Il layout dell'LLM non si legge (%@): nulla è cambiato.",
    .composeNeedsIdea: "Scrivi prima l'idea.",
  ]
}
