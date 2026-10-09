import Foundation

/// What a request to the LLM needs, for choosing the model.
public struct LanguageModelNeeds: Equatable, Sendable {
  /// The Control tab has pictures (a start image, or a Moodboard picture that is on for a family that reads it):
  /// decides which uses (I2I / T2I) apply.
  public var controlHasImages: Bool
  /// The request carries pictures, so the LLM must read them.
  public var needsImages: Bool

  public init(controlHasImages: Bool = false, needsImages: Bool = false) {
    self.controlHasImages = controlHasImages
    self.needsImages = needsImages
  }
}
