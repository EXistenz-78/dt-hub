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

  /// A model that reasons by default would spend the tokens on its reasoning: thinking is off.
  private static func options(system: String) -> LanguageModelOptions {
    LanguageModelOptions(system: system, maxTokens: 2048, thinking: false)
  }
}
