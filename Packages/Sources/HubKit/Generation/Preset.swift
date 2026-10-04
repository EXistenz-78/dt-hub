import Foundation

/// A named recipe (spec §6, and `2026-10-04-preset-pipeline-design.md`): the model, the parameters (LoRAs and
/// Advanced cards included), the prompt and the negative prompt. The size is not part of a preset: loading one
/// never changes the canvas.
public struct Preset: Equatable, Codable, Sendable, Identifiable {
  public var id: UUID
  public var name: String
  /// Empty when the preset names no model: loading it leaves the model as it is.
  public var model: String
  /// Empty when the preset has none: loading it leaves the tab's prompt as it is.
  public var prompt: String
  public var negativePrompt: String
  public var parameters: GenerationParameters
  /// The identifier of the plug-in that added the preset; nil for the user's own.
  public var origin: String?

  public init(
    id: UUID = UUID(), name: String, model: String = "", prompt: String = "", negativePrompt: String = "",
    parameters: GenerationParameters = .default, origin: String? = nil
  ) {
    self.id = id
    self.name = name
    self.model = model
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.parameters = parameters
    self.origin = origin
  }

  /// Lenient, like the other saved formats.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
    name = try container.decode(String.self, forKey: .name)
    model = (try? container.decodeIfPresent(String.self, forKey: .model)) ?? ""
    prompt = (try? container.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
    negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
    origin = try? container.decodeIfPresent(String.self, forKey: .origin)
    parameters = (try? container.decodeIfPresent(GenerationParameters.self, forKey: .parameters)) ?? .default
  }
}
