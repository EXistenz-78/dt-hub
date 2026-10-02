import HubKit

/// Builds the batches of a RUN from what the Generation tab shows (spec §6): fields the
/// model's family does not use are left out, and so are LoRAs that are not usable. Advanced
/// fields the model does not use go back to their defaults; a refiner, upscaler or face
/// restorer the server does not list is left out; a Hires fix without a start size starts
/// from the model's native size, and is dropped when that is not smaller than the image.
public enum JobComposer {
  public static func batches(
    prompt: String, negativePrompt: String, model: String, family: String?,
    parameters: GenerationParameters, catalog: ModelCatalog, imageStrength: Double? = nil,
    moodboardCount: Int = 0, maskSettings: MaskSettings? = nil, randomSeed draw: () -> UInt32 = { UInt32.random(in: .min ... .max) }
  ) -> [GenerationJob] {
    let traits = FamilyTraits.of(family)
    var sent = parameters
    sent.loras = parameters.loras.filter { catalog.status(of: $0, family: family) == .usable }
    if !traits.usesShift { sent.cfgZeroStar = false }
    sent.advanced = advanced(parameters, model: catalog.model(forFile: model), catalog: catalog)
    let negative = traits.usesNegativePrompt ? negativePrompt : ""
    return sent.batchesForRun(randomSeed: draw).map {
      GenerationJob(
        prompt: prompt, negativePrompt: negative, model: model, parameters: $0, imageStrength: imageStrength,
        moodboardCount: moodboardCount, maskSettings: maskSettings)
    }
  }

  static func advanced(_ parameters: GenerationParameters, model: CatalogModel?, catalog: ModelCatalog)
    -> AdvancedParameters
  {
    var advanced = parameters.advanced
    for field in AdvancedField.allCases where !field.isShown(for: model, sampler: parameters.sampler) {
      advanced.reset(field)
    }
    if !advanced.refinerModel.isEmpty, catalog.model(forFile: advanced.refinerModel) == nil {
      advanced.reset(.refiner)
    }
    if !advanced.upscaler.isEmpty, !catalog.upscalers.contains(advanced.upscaler) { advanced.reset(.upscaler) }
    if !advanced.faceRestoration.isEmpty, !catalog.faceRestorers.contains(advanced.faceRestoration) {
      advanced.reset(.faceRestoration)
    }
    if advanced.hiresFix {
      // One factor for both sides: the start keeps the image's proportions, its long side at
      // most the native size.
      let native = model?.capabilities.nativeSize ?? 512
      let factor = min(1, Double(native) / Double(max(parameters.width, parameters.height)))
      if advanced.hiresFixWidth == 0 { advanced.hiresFixWidth = GenerationParameters.snap(Double(parameters.width) * factor) }
      if advanced.hiresFixHeight == 0 { advanced.hiresFixHeight = GenerationParameters.snap(Double(parameters.height) * factor) }
      if advanced.hiresFixWidth >= parameters.width, advanced.hiresFixHeight >= parameters.height {
        advanced.reset(.hiresFix)
      }
    }
    return advanced
  }
}
