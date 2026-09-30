import HubKit

extension GenerationParameters {
  /// The parameters of one RUN: clamped, with a concrete seed. A random seed is drawn here,
  /// not by the server, so the saved image and "Resume parameters" know the seed used.
  public func resolvedForRun(randomSeed draw: () -> UInt32 = { UInt32.random(in: .min ... .max) })
    -> GenerationParameters
  {
    var resolved = clamped()
    if randomSeed { resolved.seed = draw() }
    resolved.randomSeed = false
    return resolved
  }
}
