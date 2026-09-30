import CoreGraphics

/// One RUN, as sent to the backend: everything is resolved (the seed included).
public struct GenerationJob: Equatable, Codable, Sendable {
  public let prompt: String
  public let model: String
  public let parameters: GenerationParameters

  public init(prompt: String, model: String, parameters: GenerationParameters) {
    self.prompt = prompt
    self.model = model
    self.parameters = parameters
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
