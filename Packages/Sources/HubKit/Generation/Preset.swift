import Foundation

/// A named recipe (spec §6, and `2026-10-04-preset-pipeline-design.md`): the model, the parameters (LoRAs and
/// Advanced cards included), the prompt and the negative prompt. The size is not part of a preset: loading one
/// never changes the canvas.
///
/// A preset is a file, `<name>.json`, in the Presets folder: the name is the file's name and is not in the JSON.
public struct Preset: Equatable, Codable, Sendable, Identifiable {
  public var name: String
  public var id: String { name }
  /// Empty when the preset names no model: loading it leaves the model as it is.
  public var model: String
  /// Empty when the preset has none: loading it leaves the tab's prompt as it is.
  public var prompt: String
  public var negativePrompt: String
  public var parameters: GenerationParameters

  public init(
    name: String, model: String = "", prompt: String = "", negativePrompt: String = "",
    parameters: GenerationParameters = .default
  ) {
    self.name = name
    self.model = model
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.parameters = parameters
  }

  /// The name is not part of the JSON.
  private enum CodingKeys: String, CodingKey {
    case model, prompt, negativePrompt, parameters
  }

  /// Lenient, like the other saved formats; the name is set by whoever read the file.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = ""
    model = (try? container.decodeIfPresent(String.self, forKey: .model)) ?? ""
    prompt = (try? container.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
    negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
    parameters = (try? container.decodeIfPresent(GenerationParameters.self, forKey: .parameters)) ?? .default
  }
}
