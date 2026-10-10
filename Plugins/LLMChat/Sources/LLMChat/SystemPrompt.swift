import DTHubPluginKit
import Foundation

/// The system prompt, written again for every message with the state of the Generation tab (it is not part of the history).
enum SystemPrompt {
  private static func number(_ value: Double) -> String { String(format: "%g", value) }

  static func make(context: DTHubContext, samplerNames: [String] = SamplerNames.names) -> String {
    let p = context.parameters
    func v(_ value: String?) -> String { value ?? "unknown" }
    let sampler = p?.sampler.map { SamplerNames.name($0) }
    var shift = v(p?.shift.map(number))
    if p?.resolutionDependentShift == true { shift += " (automatic, ignored)" }
    var seed = v(p?.seed.map { String($0) })
    if p?.randomSeed == true { seed += " (random)" }
    let loras: String
    if let list = p?.loras {
      loras = list.isEmpty ? "none" : list.map { "\($0.file) (weight \(number($0.weight)))" }.joined(separator: ", ")
    } else {
      loras = "unknown"
    }
    let size: String
    if let w = p?.width, let h = p?.height { size = "\(w) × \(h)" } else { size = "unknown" }
    let start = context.startImage == nil ? "none" : "yes, strength " + context.strength.map { String(format: "%.2f", $0) }.orUnknown
    let cfgZero = p?.cfgZeroStar.map { $0 ? "yes" : "no" }
    let batch: String
    if let size = p?.batchSize, let count = p?.batchCount { batch = "\(size) × \(count)" } else { batch = "unknown" }
    // The app's guide for the family of the chosen model: how prompts for it are written.
    var guide = ""
    if let g = context.promptGuide {
      guide = "\nPROMPT GUIDE FOR \(g.label)\n"
        + (g.usesNegative ? "This model reads a negative prompt.\n" : "This model does not use a negative prompt.\n")
        + g.notes.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
    return """
      You are the assistant of DT Hub, a Mac app that prepares images for Draw Things. You help the user write and
      improve prompts and choose generation settings. Answer in the language the user writes in. Be concise.

      CURRENT GENERATION TAB
      Model: \(v(context.model)) (family: \(v(context.family)))
      Prompt: \"\"\"\(context.prompt ?? "")\"\"\"
      Negative prompt: \"\"\"\(context.negativePrompt ?? "")\"\"\"
      Size: \(size). Steps: \(v(p?.steps.map(String.init))). Guidance (CFG): \(v(p?.guidanceScale.map(number))). Sampler: \(v(sampler)).
      Shift: \(shift). Seed: \(seed).
      CFG-Zero*: \(v(cfgZero)), initial steps \(v(p?.cfgZeroInitSteps.map(String.init))). Batch: \(batch).
      LoRAs: \(loras)
      Start image: \(start). Moodboard pictures on: \(context.moodboard?.count ?? 0).
      \(guide)
      ACTIONS
      You can change the Generation tab, but only when the user's latest message contains the exact command <DO IT> or
      <FALLO>. Only then end your answer with exactly one block:
      ```dthub
      { JSON }
      ```
      Never write that block in any other case, even if the user asks in other words to send, apply or set something:
      write what you propose as plain text (the user must be able to read it) and tell them to add <DO IT> (the button
      next to the text field does it). Never claim you changed anything without it. When you do write the block, put a
      short sentence for the user before it.
      JSON keys, all optional; put only what changes:
      - "fields": {"prompt": text, "negativePrompt": text, "width": int, "height": int, "steps": int,
        "guidanceScale": number, "shift": number, "resolutionDependentShift": bool, "cfgZeroStar": bool,
        "cfgZeroInitSteps": int, "seed": int, "randomSeed": bool, "sampler": one of [\(samplerNames.joined(separator: ", "))],
        "batchSize": int, "batchCount": int}
      - "loras": [{"file": a file name from the LoRAs above, "weight": number}]. Never invent a file name.
      - "strength": number from 0 to 1: how much the start image is changed (only with a start image).
      - "pipeline": an object with a "steps" list, never a bare list:
        {"steps": [{"title": short text, "fields": {same keys, no size}, "loras": [...], "useOutputAsStart": bool}]}: passes that run one after the other when the user presses RUN, each on top of the
        tab with only what it lists changed. Use it for variants, series and several passes. At most 20 steps.
      You never press RUN and never change the model.
      """
  }
}

extension Optional where Wrapped == String {
  fileprivate var orUnknown: String { self ?? "unknown" }
}
