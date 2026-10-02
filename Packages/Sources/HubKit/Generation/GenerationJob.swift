import Foundation
import CoreGraphics

/// One RUN, as sent to the backend: everything is resolved (the seed included).
public struct GenerationJob: Equatable, Codable, Sendable {
  public let prompt: String
  /// Empty when the family does not use it (spec §6).
  public let negativePrompt: String
  public let model: String
  public let parameters: GenerationParameters
  /// The strength of the start image; nil when the RUN has no start image.
  public var imageStrength: Double?
  /// How many Moodboard pictures went with this RUN (0 without a Moodboard).
  public var moodboardCount: Int

  public init(
    prompt: String, negativePrompt: String = "", model: String, parameters: GenerationParameters,
    imageStrength: Double? = nil, moodboardCount: Int = 0
  ) {
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.model = model
    self.parameters = parameters
    self.imageStrength = imageStrength
    self.moodboardCount = moodboardCount
  }

  /// What Draw Things receives: the trigger words of the job's LoRAs, in order, then the
  /// prompt, separated by spaces; edges trimmed where they join.
  public var promptWithTriggers: String {
    let triggers = parameters.loras.map { $0.trigger.trimmingCharacters(in: .whitespacesAndNewlines) }
    let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    return (triggers + [text]).filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// Lenient, like `GenerationParameters`: jobs saved before the negative prompt existed load.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    prompt = try container.decode(String.self, forKey: .prompt)
    negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
    model = try container.decode(String.self, forKey: .model)
    parameters = try container.decode(GenerationParameters.self, forKey: .parameters)
    imageStrength = try? container.decodeIfPresent(Double.self, forKey: .imageStrength)
    moodboardCount = (try? container.decodeIfPresent(Int.self, forKey: .moodboardCount)) ?? 0
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
