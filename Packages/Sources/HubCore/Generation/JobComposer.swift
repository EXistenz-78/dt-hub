import HubKit

/// Builds the batches of a RUN from what the Generation tab shows (spec §6): fields the
/// model's family does not use are left out, and so are LoRAs that are not usable.
public enum JobComposer {
  public static func batches(
    prompt: String, negativePrompt: String, model: String, family: String?,
    parameters: GenerationParameters, catalog: ModelCatalog,
    randomSeed draw: () -> UInt32 = { UInt32.random(in: .min ... .max) }
  ) -> [GenerationJob] {
    let traits = FamilyTraits.of(family)
    var sent = parameters
    sent.loras = parameters.loras.filter { catalog.status(of: $0, family: family) == .usable }
    if !traits.usesShift { sent.cfgZeroStar = false }
    let negative = traits.usesNegativePrompt ? negativePrompt : ""
    return sent.batchesForRun(randomSeed: draw).map {
      GenerationJob(prompt: prompt, negativePrompt: negative, model: model, parameters: $0)
    }
  }
}
