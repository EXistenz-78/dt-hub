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

  /// Qwen's recommended settings, the same as Prompt Master's PE: the enhancer's system prompt makes it reason before it
  /// answers, so it needs thinking on (the reasoning stays in `<think>`) and room for it. With thinking off and a small
  /// budget it reasoned in plain text and ran out of tokens before the answer.
  static let options = DTHubLLMOptions(
    temperature: 1.0, topP: 0.95, topK: 20, presencePenalty: 1.5, maxTokens: 16256, thinking: true, timeout: 900)

  /// The rewritten prompt in the answer, and nothing else: the reasoning (`<think>…</think>`; one that never closes
  /// takes the rest with it) and code fences go, a JSON object gives its `rewritten_prompt` (the format the enhancer's
  /// system prompt asks for), a plain text is the prompt itself without blank space and outer quotes. Nil when nothing is left.
  static func cleaned(_ answer: String) -> String? {
    var text = answer
    if let close = text.range(of: "</think>", options: .backwards) { text = String(text[close.upperBound...]) }
    if let open = text.range(of: "<think>") { text = String(text[..<open.lowerBound]) }
    text = withoutFences(text).trimmingCharacters(in: .whitespacesAndNewlines)
    if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
      let object = (try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8))) as? [String: Any],
      let prompt = (object["rewritten_prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty
    {
      return prompt
    }
    for (open, close) in [("\"", "\""), ("“", "”"), ("«", "»")] where text.count >= 2 && text.hasPrefix(open) && text.hasSuffix(close) {
      text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
      break
    }
    return text.isEmpty ? nil : text
  }

  /// The inside of a fenced block (```json … ```), when the text is one.
  private static func withoutFences(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```"), let firstBreak = trimmed.firstIndex(of: "\n") else { return text }
    var inside = String(trimmed[trimmed.index(after: firstBreak)...])
    if let close = inside.range(of: "```", options: .backwards) { inside = String(inside[..<close.lowerBound]) }
    return inside
  }
}
