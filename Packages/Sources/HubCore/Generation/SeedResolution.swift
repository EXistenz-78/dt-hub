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

extension GenerationParameters {
  /// A RUN split into its batches, sent one after the other: each has batch count 1 and its
  /// own seed, so every image records the seed that really made it and Stop keeps the batches
  /// already finished. Fixed seed: seed, seed+1, …; random: a new seed for each batch.
  public func batchesForRun(randomSeed draw: () -> UInt32 = { UInt32.random(in: .min ... .max) })
    -> [GenerationParameters]
  {
    let base = resolvedForRun(randomSeed: draw)
    return (0..<base.batchCount).map { index in
      var batch = base
      batch.batchCount = 1
      if index > 0 { batch.seed = randomSeed ? draw() : base.seed &+ UInt32(index) }
      return batch
    }
  }
}
