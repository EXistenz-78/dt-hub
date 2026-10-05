import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here (the tests check both languages are complete).
enum L {
  enum Key: CaseIterable {
    // The list
    case terms, search, photo, art, shuffle, noMatches, addTerm, addTermPlaceholder, removeTerm, customTerm
    // The description
    case description, descriptionPlaceholder, sceneShuffle, sceneWriting
    // The chosen terms and the button
    case chosen, clearAll, removeChosen, noneChosen, writePrompt, writing, booru
    // What happened
    case sent, sentWithConflicts, notAnswered, noMasterPrompt, emptyAnswer, llmFailed, sceneFailed
    case enhancerModelMissingT2I, enhancerModelMissingI2I, enhancerSystemMissing, ratio, provisional
    case unreadableFile, unknownSchema, customNotSaved
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
    .terms: "Terms", .search: "Search", .photo: "Photo", .art: "Art", .shuffle: "Shuffle",
    .noMatches: "No term matches.", .addTerm: "Add a term", .addTermPlaceholder: "Your term",
    .removeTerm: "Remove this term", .customTerm: "Your own term",
    .description: "Description", .descriptionPlaceholder: "Subject, scene and action, in any language",
    .sceneShuffle: "Shuffle scene", .sceneWriting: "Thinking of a scene…",
    .chosen: "Chosen terms", .clearAll: "Clear the list", .removeChosen: "Remove", .noneChosen: "No term chosen yet.",
    .writePrompt: "Write prompt", .writing: "Writing…", .booru: "Booru tags",
    .sent: "Prompt sent to Generation.", .sentWithConflicts: "Prompt sent. %d conflict(s) waiting in the app.",
    .notAnswered: "No answer from the app.", .noMasterPrompt: "This model has no master prompt.",
    .emptyAnswer: "The language model's answer had no prompt in it.", .llmFailed: "%@",
    .sceneFailed: "No scene: %@",
    .enhancerModelMissingT2I: "Prompt enhancer (T2I) not found in the models folder: using the language model you chose.",
    .enhancerModelMissingI2I: "Prompt enhancer (I2I) not found in the models folder: using the language model you chose.",
    .enhancerSystemMissing: "The enhancer %@ has no system_prompt.txt in its folder: using the language model you chose.",
    .ratio: "Suggested format: %@", .provisional: "This family's master prompt is provisional.",
    .unreadableFile: "%@ cannot be read: using the copy built into the plug-in.",
    .unknownSchema: "%@ has a layout this plug-in does not know: using the copy built into the plug-in.",
    .customNotSaved: "Could not save your term.",
  ]

  private static let it: [Key: String] = [
    .terms: "Termini", .search: "Cerca", .photo: "Foto", .art: "Arte", .shuffle: "Shuffle",
    .noMatches: "Nessun termine corrisponde.", .addTerm: "Aggiungi un termine", .addTermPlaceholder: "Il tuo termine",
    .removeTerm: "Togli questo termine", .customTerm: "Un tuo termine",
    .description: "Descrizione", .descriptionPlaceholder: "Soggetto, scena e azione, in qualsiasi lingua",
    .sceneShuffle: "Shuffle scena", .sceneWriting: "Penso a una scena…",
    .chosen: "Termini scelti", .clearAll: "Svuota l'elenco", .removeChosen: "Togli", .noneChosen: "Nessun termine scelto.",
    .writePrompt: "Scrivi prompt", .writing: "Sto scrivendo…", .booru: "Tag booru",
    .sent: "Prompt inviato alla Generazione.", .sentWithConflicts: "Prompt inviato. %d conflitti in attesa nell'app.",
    .notAnswered: "Nessuna risposta dall'app.", .noMasterPrompt: "Questo modello non ha un master prompt.",
    .emptyAnswer: "La risposta del modello linguistico non conteneva un prompt.", .llmFailed: "%@",
    .sceneFailed: "Nessuna scena: %@",
    .enhancerModelMissingT2I: "Il prompt enhancer (T2I) non è nella cartella dei modelli: uso il modello linguistico scelto.",
    .enhancerModelMissingI2I: "Il prompt enhancer (I2I) non è nella cartella dei modelli: uso il modello linguistico scelto.",
    .enhancerSystemMissing: "Nella cartella di %@ manca system_prompt.txt: uso il modello linguistico scelto.",
    .ratio: "Formato consigliato: %@", .provisional: "Il master prompt di questa famiglia è provvisorio.",
    .unreadableFile: "%@ non si legge: uso la copia incorporata nel plug-in.",
    .unknownSchema: "%@ ha un formato che questo plug-in non conosce: uso la copia incorporata.",
    .customNotSaved: "Non si è potuto salvare il tuo termine.",
  ]
}
