import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here.
enum L {
  enum Key: CaseIterable {
    // The tab.
    case chooseImage, dropImage, characterName, staticPrompt, llmModel, noModelsShown
    case prepare, openFolder, active, inactive
    // The status line.
    case needImage, noFolder, noVisionModel, templateMissing, templateEmpty, peSystemMissing
    case sendingImage, writingBrief, doneStatic, doneLLM
    case emptyAnswer, llmFailed, notAnswered, copyFailed
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

  static func format(_ key: Key, _ args: CVarArg..., italian: Bool = systemIsItalian) -> String {
    String(format: text(key, italian: italian), arguments: args)
  }

  private static let en: [Key: String] = [
    .chooseImage: "Choose…", .dropImage: "Drop an image here", .characterName: "Character name",
    .staticPrompt: "Static prompt", .llmModel: "Language model", .noModelsShown: "No model with vision",
    .prepare: "Prepare", .openFolder: "Open folder", .active: "active", .inactive: "not active",
    .needImage: "Choose an image first.",
    .noFolder: "No picture folder yet: switch the plug-in on first.",
    .noVisionModel: "No language model with vision: use the static prompt, or add one to the models folder.",
    .templateMissing: "%@ is missing in %@.", .templateEmpty: "%@ is empty.",
    .peSystemMissing: "%@ needs its system_prompt.txt next to the weights.",
    .sendingImage: "Sending the image to the Moodboard…", .writingBrief: "The model is writing the brief…",
    .doneStatic: "Static prompt written. Image in the Moodboard, canvas 2304×1536.",
    .doneLLM: "Prompt written: %d words in %d s.",
    .emptyAnswer: "The model gave no usable answer.", .llmFailed: "The model did not answer: %@",
    .notAnswered: "No answer from the app.", .copyFailed: "Could not copy the image.",
  ]

  private static let it: [Key: String] = [
    .chooseImage: "Scegli…", .dropImage: "Trascina qui un'immagine", .characterName: "Nome del personaggio",
    .staticPrompt: "Prompt statico", .llmModel: "Modello LLM", .noModelsShown: "Nessun modello con visione",
    .prepare: "Prepara", .openFolder: "Apri cartella", .active: "attivo", .inactive: "non attivo",
    .needImage: "Prima scegli un'immagine.",
    .noFolder: "La cartella delle immagini non c'è ancora: prima accendi il plug-in.",
    .noVisionModel: "Nessun modello con visione: usa il prompt statico, oppure aggiungine uno alla cartella dei modelli.",
    .templateMissing: "Manca %@ in %@.", .templateEmpty: "%@ è vuoto.",
    .peSystemMissing: "%@ ha bisogno del suo system_prompt.txt accanto ai pesi.",
    .sendingImage: "Mando l'immagine al Moodboard…", .writingBrief: "Il modello scrive il brief…",
    .doneStatic: "Prompt statico scritto. Immagine nel Moodboard, canvas 2304×1536.",
    .doneLLM: "Prompt scritto: %d parole in %d s.",
    .emptyAnswer: "Il modello non ha dato una risposta utilizzabile.", .llmFailed: "Il modello non ha risposto: %@",
    .notAnswered: "Nessuna risposta dall'app.", .copyFailed: "Non si è potuta copiare l'immagine.",
  ]
}
