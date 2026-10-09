import Foundation

/// Incremental mode: the result of a RUN becomes the start image of the next one.
public enum IncrementalRun {
  /// The picture to use as the start image after a RUN, or nil: when the mode is off, the RUN failed or was
  /// stopped, or nothing new reached the strip (`before` is the id on top of the strip before the RUN).
  @MainActor
  public static func output(
    enabled: Bool, phase: GenerationSession.Phase, stopped: Bool, before: GeneratedImage.ID?,
    results: [GeneratedImage]
  ) -> GeneratedImage? {
    guard enabled, !stopped else { return nil }
    if case .failed = phase { return nil }
    return PipelineInputs.output(after: before, in: results)
  }
}
