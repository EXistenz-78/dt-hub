import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here.
enum L {
  enum Key: CaseIterable {
    case needsNewApp, notActive, noLoRAs, unreadableStore, listTitle, adviceTitle, filterPlaceholder, findPages, summariseAll, jobsNote, stop, progress, currentModel, unknownFamily, trigger, noTrigger, weight, noNotes, foundAuto, pageNotFound, toSummarise, add, onTab, otherFamily,
      notes, link, importPage, cancel, summarise, notThisOne, searchAgain, thumbnail, chooseFile, useControlImage, removeThumbnail, unreadableImage, replaceNotesQuestion, replace, keepMine, linkNotRecognised, needsAccess, noImageInPage, notFound, unreachable, unreadableAnswer, tooLarge, notAllowed,
      rateLimited, imported, summaryFailed,
      needsLLM, request, onlyFamily, advise, resetRequest, noSuitable, adviceNotUnderstood, noLoRAsForFamily, updateWeight, addAll, sent, sentWithConflicts, notAnswered, languageName
  }

  static var systemIsItalian: Bool {
    Locale.preferredLanguages.first?.hasPrefix("it") ?? false
  }

  static func text(_ key: Key, italian: Bool = systemIsItalian) -> String {
    (italian ? it : en)[key] ?? en[key] ?? "\(key)"
  }

  /// A text with numbers or words in it (`%d`, `%@`).
  static func text(_ key: Key, _ arguments: any CVarArg..., italian: Bool = systemIsItalian) -> String {
    String(format: text(key, italian: italian), arguments: arguments)
  }

  /// Whether the word is in the table of that language (the tests check both are complete).
  static func isDefined(_ key: Key, italian: Bool) -> Bool {
    (italian ? it : en)[key] != nil
  }

  private static let it: [Key: String] = [
    .needsNewApp: "Serve DT Hub 0.2.2 o successivo per l'elenco dei LoRA.",
    .notActive: "Accendi LoRA Advisor per il lavoro (menu dell'header) per vedere i tuoi LoRA.",
    .noLoRAs: "Il server non ha LoRA.",
    .unreadableStore: "Il file delle note non si legge: resta com'è finché non modifichi qualcosa.",
    .listTitle: "I tuoi LoRA",
    .adviceTitle: "Consiglia",
    .filterPlaceholder: "Filtra per nome, trigger o note",
    .findPages: "Cerca le pagine · %d",
    .summariseAll: "Riassumi tutti · %d",
    .jobsNote: "lavorano solo sui LoRA nuovi o senza pagina",
    .stop: "Ferma",
    .progress: "%d di %d",
    .currentModel: "modello attuale",
    .unknownFamily: "Famiglia sconosciuta",
    .trigger: "trigger: %@",
    .noTrigger: "nessun trigger",
    .weight: "peso %@",
    .noNotes: "Nessuna nota.",
    .foundAuto: "trovato automaticamente",
    .pageNotFound: "pagina non trovata",
    .toSummarise: "da riassumere",
    .add: "Aggiungi",
    .onTab: "già nella lista",
    .otherFamily: "È di un'altra famiglia di modelli.",
    .notes: "Note",
    .link: "Link alla pagina (Civitai o Hugging Face)",
    .importPage: "Importa dalla pagina",
    .cancel: "Annulla",
    .summarise: "Riassumi",
    .notThisOne: "Non è questo",
    .searchAgain: "Cerca di nuovo",
    .thumbnail: "Anteprima",
    .chooseFile: "Scegli file…",
    .useControlImage: "Usa l'immagine di Control",
    .removeThumbnail: "Rimuovi",
    .unreadableImage: "Immagine non leggibile.",
    .replaceNotesQuestion: "Sostituire le note con il testo della pagina?",
    .replace: "Sostituisci",
    .keepMine: "Tieni le mie",
    .linkNotRecognised: "Link non riconosciuto: servono una pagina di Civitai o di Hugging Face.",
    .needsAccess: "Questa pagina richiede l'accesso. Scegli tu un'immagine e scrivi le note.",
    .noImageInPage: "Nessuna immagine nella pagina.",
    .notFound: "Pagina non trovata.",
    .unreachable: "La pagina non risponde.",
    .unreadableAnswer: "Risposta non leggibile.",
    .tooLarge: "Immagine troppo grande.",
    .notAllowed: "Indirizzo non ammesso.",
    .rateLimited: "Civitai chiede di rallentare: riprova più tardi.",
    .imported: "Pagina importata.",
    .summaryFailed: "Riassunto non riuscito.",
    .needsLLM: "Serve un LLM assegnato ai plug-in (Preferenze › LLM).",
    .request: "Richiesta",
    .onlyFamily: "Solo i LoRA di %@",
    .advise: "Consiglia",
    .resetRequest: "Torna al prompt attuale",
    .noSuitable: "Nessun LoRA adatto.",
    .adviceNotUnderstood: "Non ho capito la risposta dell'LLM.",
    .noLoRAsForFamily: "Nessun LoRA per questa famiglia.",
    .updateWeight: "Aggiorna il peso",
    .addAll: "Aggiungi tutti",
    .sent: "Aggiunto a Generazione.",
    .sentWithConflicts: "Aggiunto. %d conflitto/i da risolvere.",
    .notAnswered: "L'app non ha risposto: il plug-in è acceso per il lavoro?",
    .languageName: "italiano",
  ]

  private static let en: [Key: String] = [
    .needsNewApp: "DT Hub 0.2.2 or later is needed for the list of LoRAs.",
    .notActive: "Turn LoRA Advisor on for the job (header menu) to see your LoRAs.",
    .noLoRAs: "The server has no LoRAs.",
    .unreadableStore: "The notes file cannot be read: it stays as it is until you change something.",
    .listTitle: "Your LoRAs",
    .adviceTitle: "Advise",
    .filterPlaceholder: "Filter by name, trigger or notes",
    .findPages: "Find pages · %d",
    .summariseAll: "Summarise all · %d",
    .jobsNote: "they only work on new LoRAs or those without a page",
    .stop: "Stop",
    .progress: "%d of %d",
    .currentModel: "current model",
    .unknownFamily: "Unknown family",
    .trigger: "trigger: %@",
    .noTrigger: "no trigger",
    .weight: "weight %@",
    .noNotes: "No notes.",
    .foundAuto: "found automatically",
    .pageNotFound: "page not found",
    .toSummarise: "to summarise",
    .add: "Add",
    .onTab: "already in the list",
    .otherFamily: "It is for another family of models.",
    .notes: "Notes",
    .link: "Link to the page (Civitai or Hugging Face)",
    .importPage: "Import from the page",
    .cancel: "Cancel",
    .summarise: "Summarise",
    .notThisOne: "Not this one",
    .searchAgain: "Search again",
    .thumbnail: "Thumbnail",
    .chooseFile: "Choose File…",
    .useControlImage: "Use the Control Image",
    .removeThumbnail: "Remove",
    .unreadableImage: "The image cannot be read.",
    .replaceNotesQuestion: "Replace the notes with the text of the page?",
    .replace: "Replace",
    .keepMine: "Keep Mine",
    .linkNotRecognised: "Link not recognised: a Civitai or Hugging Face page is needed.",
    .needsAccess: "This page needs an account. Choose a picture and write the notes yourself.",
    .noImageInPage: "No picture in the page.",
    .notFound: "Page not found.",
    .unreachable: "The page does not answer.",
    .unreadableAnswer: "The answer cannot be read.",
    .tooLarge: "The picture is too large.",
    .notAllowed: "Address not allowed.",
    .rateLimited: "Civitai asks to slow down: try again later.",
    .imported: "Page imported.",
    .summaryFailed: "The summary failed.",
    .needsLLM: "A language model assigned to plug-ins is needed (Settings › LLM).",
    .request: "Request",
    .onlyFamily: "Only the LoRAs for %@",
    .advise: "Advise",
    .resetRequest: "Back to the current prompt",
    .noSuitable: "No suitable LoRA.",
    .adviceNotUnderstood: "The language model's answer could not be understood.",
    .noLoRAsForFamily: "No LoRAs for this family.",
    .updateWeight: "Update the Weight",
    .addAll: "Add All",
    .sent: "Added to Generation.",
    .sentWithConflicts: "Added. %d conflict(s) to resolve.",
    .notAnswered: "The app did not answer: is the plug-in on for the job?",
    .languageName: "English",
  ]
}
