import DTHubPluginKit
import Foundation

/// One question for the language model.
struct CSRequest: Equatable {
  /// The name of the model, as `DTHubContext.languageModels` lists it.
  let model: String
  let prompt: String
  let images: [String]
  let system: String
  let options: DTHubLLMOptions
}

/// The two ways of asking for the character sheet brief (spec §3.2).
enum CSBrief {
  /// Qwen's prompt enhancer for image editing keeps its own system prompt next to the weights.
  static let peSystemFileNames = ["system_prompt.txt", "system_prompt_i2i.txt"]

  /// The settings of the workflow's author: the model thinks first, and the brief is long (a low limit gives an
  /// empty answer).
  private static let genericOptions = DTHubLLMOptions(
    temperature: 0.9, topP: 0.95, topK: 20, maxTokens: 16384, thinking: true, timeout: 900)
  /// Qwen's recommended settings for the image-editing enhancer (it thinks for minutes).
  private static let peOptions = DTHubLLMOptions(
    temperature: 1.0, topP: 0.95, topK: 20, presencePenalty: 0, maxTokens: 24000, thinking: true, timeout: 1800)

  /// `-` and `.` read as `_`, in lower case: `Qwen-Image-2.1-PE-I2I-MLX-4bit` and `qwen3.5_9b_qwen_image_2.1_pe_i2i`
  /// both match (same rule as Prompt Master's enhancer lookup).
  static func isPEI2I(_ modelName: String) -> Bool {
    let normalized = String(modelName.lowercased().map { $0 == "-" || $0 == "." ? "_" : $0 })
    return normalized.contains("qwen_image_2_1_pe_i2i")
  }

  /// The first non-empty system prompt file in the model's folder.
  static func peSystem(inFolder folder: URL, read: (URL) -> String?) -> String? {
    for name in peSystemFileNames {
      if let text = read(folder.appendingPathComponent(name))?.trimmingCharacters(in: .whitespacesAndNewlines),
        !text.isEmpty
      {
        return text
      }
    }
    return nil
  }

  /// Any vision model: the master prompt is the system prompt, the request is the name.
  static func generic(model: String, image: String, name: String, master: String) -> CSRequest {
    CSRequest(
      model: model, prompt: "Entity name: \(displayName(name))", images: [image], system: master,
      options: genericOptions)
  }

  /// Qwen PE I2I: its own system prompt, and the master prompt as the instruction it rewrites.
  static func peI2I(model: String, image: String, name: String, master: String, peSystem: String) -> CSRequest {
    CSRequest(
      model: model, prompt: "\(master)\n\nEntity name: \(displayName(name))", images: [image], system: peSystem,
      options: peOptions)
  }

  private static func displayName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? CSTemplates.fallbackName : trimmed
  }
}
