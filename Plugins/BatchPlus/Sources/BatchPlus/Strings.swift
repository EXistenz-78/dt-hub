import Foundation

/// The words of the plug-in, in Italian and English. A plug-in bundle holds only its library, so there are no
/// `.strings` files: the table is here.
enum L {
  enum Key: CaseIterable {
    case modeParameters, modePrompts
    case model, size, steps, guidance, guidanceRow, sampler, shift, cfgZero, cfgZeroSteps, seed, batch, lora, advanced
    case yes, no, auto, random
    case samplerVary, samplerNone, samplerHint
    case increment, passes, fixedSeed, preview, pass
    case shiftAutoNote, passesWarning, previewNote
    case needsNewApp, noParameters, noIncrements, invalidIncrement
    case promptsHint, promptsCount, promptsFew
    case send, sending
    case sent, sentWithConflicts, notAnswered
    case pipelineName, promptTitle
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
    .modeParameters: "Parameters", .modePrompts: "Prompts",
    .model: "Model", .size: "Size", .steps: "Steps", .guidance: "Guidance", .guidanceRow: "Guidance (CFG)", .sampler: "Sampler", .shift: "Shift",
    .cfgZero: "CFG-Zero*", .cfgZeroSteps: "CFG-Zero* initial steps", .seed: "Seed", .batch: "Batch", .lora: "LoRA weight",
    .advanced: "Advanced",
    .yes: "yes", .no: "no", .auto: "auto", .random: "random",
    .samplerVary: "Vary…", .samplerNone: "as the tab", .samplerHint: "Pass 1 uses the first one chosen, and so on, at most one per pass; later passes keep the tab's sampler.",
    .increment: "Increment", .passes: "Passes", .fixedSeed: "Fixed seed", .preview: "Preview", .pass: "Pass %d",
    .shiftAutoNote: "Draw Things ignores the shift", .passesWarning: "That is a long series: %d RUNs.",
    .previewNote: "Values outside the allowed range are brought back into it by the app.",
    .needsNewApp: "Update DT Hub to use the Parameters mode.", .noParameters: "Waiting for the parameters of the tab…",
    .noIncrements: "Fill at least one increment.", .invalidIncrement: "An increment is not valid.",
    .promptsHint: "One prompt per bullet (-, • or *). Lines without a bullet continue the previous prompt.",
    .promptsCount: "%d prompt(s)", .promptsFew: "At least two prompts are needed.",
    .send: "Send the series", .sending: "Sending…",
    .sent: "Sent.", .sentWithConflicts: "Sent. %d conflict(s) waiting in the app.", .notAnswered: "No answer from the app.",
    .pipelineName: "Batch plus", .promptTitle: "Prompt %d",
  ]

  private static let it: [Key: String] = [
    .modeParameters: "Parametri", .modePrompts: "Prompt",
    .model: "Modello", .size: "Dimensioni", .steps: "Passi", .guidance: "Guidance", .guidanceRow: "Guidance (CFG)", .sampler: "Sampler", .shift: "Shift",
    .cfgZero: "CFG-Zero*", .cfgZeroSteps: "Passi iniziali CFG-Zero*", .seed: "Seed", .batch: "Batch", .lora: "Peso LoRA",
    .advanced: "Avanzate",
    .yes: "sì", .no: "no", .auto: "auto", .random: "casuale",
    .samplerVary: "Varia…", .samplerNone: "come la scheda", .samplerHint: "Il passaggio 1 usa il primo scelto, e così via, al massimo uno per passaggio; i passaggi successivi tengono il sampler della scheda.",
    .increment: "Incremento", .passes: "Passaggi", .fixedSeed: "Seed fisso", .preview: "Anteprima", .pass: "Passaggio %d",
    .shiftAutoNote: "Draw Things ignora lo shift", .passesWarning: "È una serie lunga: %d RUN.",
    .previewNote: "I valori fuori limite vengono riportati nei limiti dall'app.",
    .needsNewApp: "Aggiorna DT Hub per usare la modalità Parametri.", .noParameters: "In attesa dei parametri della scheda…",
    .noIncrements: "Compila almeno un incremento.", .invalidIncrement: "Un incremento non è valido.",
    .promptsHint: "Un prompt per punto elenco (-, • o *). Le righe senza segno continuano il prompt precedente.",
    .promptsCount: "%d prompt", .promptsFew: "Servono almeno due prompt.",
    .send: "Invia la serie", .sending: "Invio…",
    .sent: "Inviato.", .sentWithConflicts: "Inviato. %d conflitti in attesa nell'app.", .notAnswered: "Nessuna risposta dall'app.",
    .pipelineName: "Batch plus", .promptTitle: "Prompt %d",
  ]
}
