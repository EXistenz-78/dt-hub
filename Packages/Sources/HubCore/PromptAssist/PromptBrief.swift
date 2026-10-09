import Foundation
import HubKit

/// The prompt and the negative prompt as they sit in the fields.
public struct PromptPair: Equatable, Sendable {
  public var prompt: String
  public var negative: String

  public init(prompt: String, negative: String) {
    self.prompt = prompt
    self.negative = negative
  }
}

/// One message for the language model: text, images and options (system included).
public struct PromptRequest: Equatable, Sendable {
  public let prompt: String
  public let images: [URL]
  public let options: LanguageModelOptions
}

/// The messages the Enhance/Generate Prompt tools send to the language model (pure functions).
public enum PromptBrief {
  private static let proseRule =
    "The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives."
  private static let jsonRule =
    "The final prompt must be written exclusively in English, whatever the language of the input. Reply with a JSON object and nothing else, in this shape: {\"prompt\": \"...\", \"negative\": \"...\"}. \"prompt\" is the final prompt; \"negative\" lists only what to avoid, short and targeted. Both values are in English. No explanation, no comments, no markdown."

  public static func system(family: String?) -> String {
    let guide = PromptGuides.guide(for: family)
    let intro = guide.map { "You write prompts for the image model \"\($0.label)\"." }
      ?? "You write prompts for an image-generation model."
    var text = intro + "\n\n" + (guide?.usesNegative == true ? jsonRule : proseRule)
    if let guide { text += "\n\nModel notes:\n" + guide.notes }
    return text
  }

  public static func enhance(_ current: PromptPair, family: String?) -> PromptRequest {
    var text =
      "Improve the prompt below for this model. Keep every element it describes and never contradict it; add concrete visual detail as the model notes ask. The prompt may be in any language.\n\nPrompt:\n"
      + current.prompt
    if PromptGuides.guide(for: family)?.usesNegative == true, !current.negative.isEmpty {
      text += "\n\nNegative prompt:\n" + current.negative
    }
    return PromptRequest(prompt: text, images: [], options: options(system: system(family: family)))
  }

  public static func describe(imageAt url: URL, family: String?) -> PromptRequest {
    PromptRequest(
      prompt:
        "Describe this image as a prompt for this model, following the model notes. Describe only what is visible; do not invent a story.",
      images: [url], options: options(system: system(family: family)))
  }

  /// Enhance with an LLM that has its own system prompt: the user's text goes as it is (the model was made for
  /// exactly that), with the model's own sampling values and room to think.
  public static func enhance(
    _ current: PromptPair, ownSystem: String, generation: LanguageModelProfile.Generation?
  ) -> PromptRequest {
    PromptRequest(prompt: current.prompt, images: [], options: ownOptions(ownSystem, generation))
  }

  /// Generate with an LLM that has its own system prompt.
  public static func describe(
    imageAt url: URL, ownSystem: String, generation: LanguageModelProfile.Generation?
  ) -> PromptRequest {
    PromptRequest(
      prompt: "Describe this image as a prompt for an image-generation model.", images: [url],
      options: ownOptions(ownSystem, generation))
  }

  private static func ownOptions(_ system: String, _ generation: LanguageModelProfile.Generation?) -> LanguageModelOptions {
    LanguageModelOptions(
      system: system, temperature: generation?.temperature, topP: generation?.topP, topK: generation?.topK,
      maxTokens: 16384, thinking: true)
  }

  /// The prompt (and negative prompt) in an answer. Same logic as Prompt Master's `AnswerParser`, copied because the
  /// plug-in is a separate package. Reasoning blocks (`<think>…</think>`) and code fences go; a JSON object gives its
  /// `prompt` (or `rewritten_prompt`, `positive_prompt`) and `negative` (or `negative_prompt`); anything else, a
  /// malformed JSON included, is the prompt itself. `negative` is "" when the answer has none; nil when nothing is left.
  public static func parse(_ raw: String) -> PromptPair? {
    var text = withoutThinking(raw)
    text = withoutFences(text).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
      let object = (try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8))) as? [String: Any],
      let prompt = ["prompt", "rewritten_prompt", "positive_prompt"].lazy.compactMap({ clean(object[$0]) }).first
    {
      let negative = ["negative", "negative_prompt"].lazy.compactMap { clean(object[$0]) }.first
      return PromptPair(prompt: prompt, negative: negative ?? "")
    }
    return PromptPair(prompt: unquoted(text), negative: "")
  }

  private static func clean(_ value: Any?) -> String? {
    guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
      return nil
    }
    return text
  }

  /// Everything after the last `</think>`; a `<think>` that never closes takes the rest of the text with it.
  private static func withoutThinking(_ text: String) -> String {
    var result = text
    if let close = result.range(of: "</think>", options: .backwards) {
      result = String(result[close.upperBound...])
    }
    if let open = result.range(of: "<think>") { result = String(result[..<open.lowerBound]) }
    return result
  }

  /// The inside of a fenced block (```json … ```), when the text is one.
  private static func withoutFences(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```"), let firstBreak = trimmed.firstIndex(of: "\n") else { return text }
    var inside = String(trimmed[trimmed.index(after: firstBreak)...])
    if let close = inside.range(of: "```", options: .backwards) { inside = String(inside[..<close.lowerBound]) }
    return inside
  }

  /// A prompt wrapped in one pair of quotation marks loses them.
  private static func unquoted(_ text: String) -> String {
    for (open, close) in [("\"", "\""), ("“", "”")]
    where text.count > 1 && text.hasPrefix(open) && text.hasSuffix(close) {
      let inside = String(text.dropFirst().dropLast())
      if !inside.contains(open) { return inside.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    return text
  }

  /// A model that reasons by default would spend the tokens on its reasoning: thinking is off.
  private static func options(system: String) -> LanguageModelOptions {
    LanguageModelOptions(system: system, maxTokens: 2048, thinking: false)
  }
}
