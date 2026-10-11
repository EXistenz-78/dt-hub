import DTHubPluginKit
import Foundation

/// The system prompt, written again for every message with the state of the Generation tab (it is not part of the history).
enum SystemPrompt {
  private static func number(_ value: Double) -> String { String(format: "%g", value) }

  /// Where the rules file and the user's own are read from (every time a message is sent).
  static func folder(dataFolder: URL = defaultDataFolder) -> DTHubPromptFolder {
    DTHubPromptFolder(folder: dataFolder.appendingPathComponent("AIAssistant", isDirectory: true))
  }

  static var defaultDataFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true).appendingPathComponent("Data", isDirectory: true)
  }

  /// At launch: writes the rules if missing or older (and makes `custom/`).
  static func install(dataFolder: URL = defaultDataFolder) {
    folder(dataFolder: dataFolder).install([ChatRules.path: ChatRules.builtIn])
  }

  static func make(
    context: DTHubContext, samplerNames: [String] = SamplerNames.names, folder: DTHubPromptFolder = SystemPrompt.folder()
  ) -> String {
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
    let tab = """
      Model: \(v(context.model)) (family: \(v(context.family)))
      Prompt: \"\"\"\(context.prompt ?? "")\"\"\"
      Negative prompt: \"\"\"\(context.negativePrompt ?? "")\"\"\"
      Size: \(size). Steps: \(v(p?.steps.map(String.init))). Guidance (CFG): \(v(p?.guidanceScale.map(number))). Sampler: \(v(sampler)).
      Shift: \(shift). Seed: \(seed).
      CFG-Zero*: \(v(cfgZero)), initial steps \(v(p?.cfgZeroInitSteps.map(String.init))). Batch: \(batch).
      LoRAs: \(loras)
      Start image: \(start). Moodboard pictures on: \(context.moodboard?.count ?? 0).
      """
    // The rules (the file when valid, the built-in copy otherwise), the user's own after them; then the placeholders are
    // filled, the state of the tab last so that nothing in the user's own text is read as a placeholder.
    let rules = folder.base(ChatRules.path, embedded: ChatRules.builtIn).file.body
    let text = folder.assemble(rules: rules, family: "", extras: [], customName: "chat.md", label: "AI Assistant")
    return text
      .replacingOccurrences(of: "{samplers}", with: samplerNames.joined(separator: ", "))
      .replacingOccurrences(of: "{guide}", with: guide)
      .replacingOccurrences(of: "{tab}", with: tab)
  }
}

extension Optional where Wrapped == String {
  fileprivate var orUnknown: String { self ?? "unknown" }
}
