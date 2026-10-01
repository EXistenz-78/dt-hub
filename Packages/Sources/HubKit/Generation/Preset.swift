import Foundation

/// A named recipe (spec §6): the model, the parameters (LoRAs and Advanced cards included)
/// and the negative prompt. Never the prompt itself.
public struct Preset: Equatable, Codable, Sendable, Identifiable {
  public var id: UUID
  public var name: String
  /// Empty when the preset names no model: loading it leaves the model as it is.
  public var model: String
  public var negativePrompt: String
  public var parameters: GenerationParameters

  public init(
    id: UUID = UUID(), name: String, model: String = "", negativePrompt: String = "",
    parameters: GenerationParameters = .default
  ) {
    self.id = id
    self.name = name
    self.model = model
    self.negativePrompt = negativePrompt
    self.parameters = parameters
  }

  /// Lenient, like the other saved formats.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
    name = try container.decode(String.self, forKey: .name)
    model = (try? container.decodeIfPresent(String.self, forKey: .model)) ?? ""
    negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
    parameters = (try? container.decodeIfPresent(GenerationParameters.self, forKey: .parameters)) ?? .default
  }
}
