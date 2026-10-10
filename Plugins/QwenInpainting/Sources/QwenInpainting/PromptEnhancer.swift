import DTHubPluginKit
import Foundation

/// Qwen's prompt enhancer for image editing (PE I2I), when the user assigned one to the family: it rewrites the instructions.
enum PromptEnhancer {
  static let builtInSystem =
    "You rewrite instructions for Qwen Image 2.1 image editing. The picture has colored marks drawn on it. Rewrite the user's instructions as one clear editing prompt in English. Keep every reference to the colored marks (colour and shape) and the final instruction to remove them. Answer with the prompt only."
  static let keepLine = "Keep every reference to the colored marks and the instruction to remove them."

  /// The first by name among the models assigned to `qwen_image_2.1` with the I2I use that read images.
  static func model(in models: [DTHubLanguageModel]) -> DTHubLanguageModel? {
    models.filter { $0.family == "qwen_image_2.1" && $0.use == "i2i" && $0.supportsImages }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.first
  }

  /// `system_prompt_i2i.txt` or `system_prompt.txt` of the model's folder, else the built-in text.
  static func systemPrompt(for model: DTHubLanguageModel) -> String {
    let folder = URL(fileURLWithPath: model.path, isDirectory: true)
    for name in ["system_prompt_i2i.txt", "system_prompt.txt"] {
      if let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
      }
    }
    return builtInSystem
  }

  static func request(composed: String) -> String { composed + "\n\n" + keepLine }

  /// The answer without blank space and outer quotes; nil when nothing is left.
  static func cleaned(_ answer: String) -> String? {
    var text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    for (open, close) in [("\"", "\""), ("“", "”"), ("«", "»")] where text.count >= 2 && text.hasPrefix(open) && text.hasSuffix(close) {
      text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
      break
    }
    return text.isEmpty ? nil : text
  }
}
