import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here.
enum L {
  enum Key: CaseIterable {
    case model, images, imagesOff, newChat, chats, rename, delete, renamePrompt, deleteConfirm, cancel, ok
    case placeholder, commandButton, commandHelp, sendButton, thinking, stopWaiting
    case notActive, needsNewApp, waitingContext, noModels
    case attached, trimmed
    case ignoredNoCommand, noAction, nothingUsable, invalidBlock, tooManySteps, noAnswer
    case sent, sentConflicts, sentProblems
    case fPrompt, fNegative, fWidth, fHeight, fSteps, fGuidance, fShift, fAutoShift, fCfgZero, fCfgZeroSteps, fSeed
    case fRandomSeed, fSampler, fBatchSize, fBatchCount, fLoras, fStrength, fPipeline
    case pass, pipelineName, passesWord, loraWord
  }

  static var systemIsItalian: Bool {
    Locale.preferredLanguages.first?.hasPrefix("it") ?? false
  }

  /// The command that opens the actions, in the language of the app.
  static func command(italian: Bool = systemIsItalian) -> String { italian ? "<FALLO>" : "<DO IT>" }

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
    .model: "Model", .images: "Images", .imagesOff: "The model does not read images", .newChat: "New chat", .chats: "Chats",
    .rename: "Rename…", .delete: "Delete…", .renamePrompt: "Name of the chat", .deleteConfirm: "Delete this chat?",
    .cancel: "Cancel", .ok: "OK",
    .placeholder: "Write to the LLM…", .commandButton: "<DO IT>", .commandHelp: "Adds the command that lets the assistant apply what it proposes", .sendButton: "Send the message",
    .thinking: "Writing…", .stopWaiting: "Stop waiting",
    .notActive: "Switch AI Assistant on from the plug-ins menu.", .needsNewApp: "Update DT Hub (0.1.6 or later).",
    .waitingContext: "Waiting for the app…", .noModels: "No LLM in the models folder (Settings › LLM).",
    .attached: "%d image(s) attached", .trimmed: "The oldest messages are no longer sent to the LLM.",
    .ignoredNoCommand: "Action ignored: the message did not contain %@", .noAction: "No action in the answer.", .nothingUsable: "The action block has nothing that can be sent.",
    .invalidBlock: "The action block is not valid: %@", .tooManySteps: "The pipeline has %d passes: at most 20.",
    .noAnswer: "No answer.",
    .sent: "Sent: %@.", .sentConflicts: " %d conflict(s) waiting in the app.", .sentProblems: " Problems: %@",
    .fPrompt: "prompt", .fNegative: "negative", .fWidth: "width", .fHeight: "height", .fSteps: "steps",
    .fGuidance: "guidance", .fShift: "shift", .fAutoShift: "automatic shift", .fCfgZero: "CFG-Zero*",
    .fCfgZeroSteps: "CFG-Zero* steps", .fSeed: "seed", .fRandomSeed: "random seed", .fSampler: "sampler",
    .fBatchSize: "batch size", .fBatchCount: "batch count", .fLoras: "LoRAs", .fStrength: "strength", .fPipeline: "pipeline",
    .pass: "Pass %d", .pipelineName: "AI Assistant", .passesWord: "passes", .loraWord: "LoRAs",
  ]

  private static let it: [Key: String] = [
    .model: "Modello", .images: "Immagini", .imagesOff: "Il modello non legge immagini", .newChat: "Nuova chat", .chats: "Chat",
    .rename: "Rinomina…", .delete: "Elimina…", .renamePrompt: "Nome della chat", .deleteConfirm: "Eliminare questa chat?",
    .cancel: "Annulla", .ok: "OK",
    .placeholder: "Scrivi all'LLM…", .commandButton: "<FALLO>", .commandHelp: "Aggiunge il comando che permette all'assistente di applicare ciò che propone", .sendButton: "Manda il messaggio",
    .thinking: "Sta scrivendo…", .stopWaiting: "Smetti di aspettare",
    .notActive: "Accendi AI Assistant dal menu dei plug-in.", .needsNewApp: "Aggiorna DT Hub (0.1.6 o successiva).",
    .waitingContext: "In attesa dell'app…", .noModels: "Nessun LLM nella cartella dei modelli (Preferenze › LLM).",
    .attached: "%d immagini allegate", .trimmed: "I messaggi più vecchi non sono più mandati all'LLM.",
    .ignoredNoCommand: "Azione ignorata: il messaggio non conteneva %@", .noAction: "Nessuna azione nella risposta.", .nothingUsable: "Il blocco di azioni non contiene nulla che si possa inviare.",
    .invalidBlock: "Il blocco di azioni non è valido: %@", .tooManySteps: "La pipeline ha %d passaggi: al massimo 20.",
    .noAnswer: "Nessuna risposta.",
    .sent: "Inviati: %@.", .sentConflicts: " %d conflitti in attesa nell'app.", .sentProblems: " Problemi: %@",
    .fPrompt: "prompt", .fNegative: "negativo", .fWidth: "larghezza", .fHeight: "altezza", .fSteps: "passi",
    .fGuidance: "guidance", .fShift: "shift", .fAutoShift: "shift automatico", .fCfgZero: "CFG-Zero*",
    .fCfgZeroSteps: "passi CFG-Zero*", .fSeed: "seed", .fRandomSeed: "seed casuale", .fSampler: "sampler",
    .fBatchSize: "dimensione batch", .fBatchCount: "numero di batch", .fLoras: "LoRA", .fStrength: "forza", .fPipeline: "pipeline",
    .pass: "Passaggio %d", .pipelineName: "AI Assistant", .passesWord: "passaggi", .loraWord: "LoRA",
  ]
}
