import Foundation
import CoreGraphics

/// One RUN, as sent to the backend: everything is resolved (the seed included).
public struct GenerationJob: Equatable, Codable, Sendable {
  public let prompt: String
  /// Empty when the family does not use it (spec §6).
  public let negativePrompt: String
  public let model: String
  public let parameters: GenerationParameters

  public init(prompt: String, negativePrompt: String = "", model: String, parameters: GenerationParameters) {
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.model = model
    self.parameters = parameters
  }

  /// What Draw Things receives: the trigger words of the job's LoRAs, in order, then the
  /// prompt, separated by spaces.
  public var promptWithTriggers: String {
    let triggers = parameters.loras.map { $0.trigger.trimmingCharacters(in: .whitespacesAndNewlines) }
    return (triggers + [prompt]).filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// Lenient, like `GenerationParameters`: jobs saved before the negative prompt existed load.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    prompt = try container.decode(String.self, forKey: .prompt)
    negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
    model = try container.decode(String.self, forKey: .model)
    parameters = try container.decode(GenerationParameters.self, forKey: .parameters)
  }
}

/// What a running generation reports, in order; `.finished` is always last.
public enum GenerationUpdate: Sendable {
  /// Sampling step `step` of `totalSteps`; nil step while encoding or decoding.
  case progress(step: Int?, totalSteps: Int)
  /// A preview of the image being sampled.
  case preview(CGImage)
  /// All the final images of the RUN.
  case finished([CGImage])
}
