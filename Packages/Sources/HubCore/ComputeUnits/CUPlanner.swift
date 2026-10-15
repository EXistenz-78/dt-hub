import HubKit

/// One request of a RUN, with what its compute-unit estimate needs (nil when it cannot be told: no model, a missing
/// preset…).
public struct CUPass: Equatable, Sendable {
  public var title: String
  public var inputs: CUInputs?

  public init(title: String, inputs: CUInputs?) {
    self.title = title
    self.inputs = inputs
  }
}

/// What the Control tab contributes to the estimate.
public struct CUControlSummary: Equatable, Sendable {
  public var hasImage: Bool
  /// The Moodboard pictures that are on.
  public var moodboardCount: Int
  /// The strength of the start image (the effective one).
  public var strength: Double

  public init(hasImage: Bool, moodboardCount: Int, strength: Double) {
    self.hasImage = hasImage
    self.moodboardCount = moodboardCount
    self.strength = strength
  }
}

/// Turns the tab, the Control tab and a held pipeline into the requests the CU meter measures (spec §5). It follows
/// `GenerationController.runPipeline` with the same functions, without running anything.
@MainActor
public enum CUPlanner {
  public static func passes(
    fields: GenerationFields, model: CatalogModel?, control: CUControlSummary, pipeline: PluginPipeline?,
    presets: [String: Preset], catalog: ModelCatalog, headerModel: String?
  ) -> [CUPass] {
    guard let pipeline else {
      return [
        CUPass(
          title: "",
          inputs: inputs(
            fields.parameters, model: model, hasImage: control.hasImage, strength: control.strength,
            references: control.moodboardCount))
      ]
    }
    var result: [CUPass] = []
    var previousSize: Size?
    for (index, step) in pipeline.steps.enumerated() {
      var used = PipelinePresets.fields(for: step, over: fields, presets: presets, catalog: catalog)
      if step.usesPresetModel, let previousSize {
        let size = PipelineSizes.scaled(previousSize, by: step.scale, limit: used.parameters.sizeLimit)
        used.parameters.width = size.width
        used.parameters.height = size.height
      }
      previousSize = Size(width: used.parameters.width, height: used.parameters.height)
      let file = PipelinePresets.model(for: step, presets: presets, header: headerModel)
      let passModel = file.flatMap { catalog.model(forFile: $0) }
      let presetMissing = !step.preset.isEmpty && presets[step.preset] == nil
      let hasImage = control.hasImage || step.startImage != nil || (step.useOutputAsStart && index > 0)
      result.append(
        CUPass(
          title: step.title,
          inputs: presetMissing
            ? nil
            : inputs(
              used.parameters, model: passModel, hasImage: hasImage, strength: step.strength ?? control.strength,
              references: step.moodboard?.count ?? control.moodboardCount)))
    }
    return result
  }

  static func inputs(
    _ parameters: GenerationParameters, model: CatalogModel?, hasImage: Bool, strength: Double, references: Int
  ) -> CUInputs? {
    guard let model, let family = model.family else { return nil }
    return CUInputs(
      family: family, modelFile: model.file, capabilities: model.capabilities, width: parameters.width,
      height: parameters.height, steps: parameters.steps, strength: hasImage ? strength : 1,
      guidanceScale: parameters.guidanceScale, batchSize: parameters.batchSize, hasImage: hasImage,
      speedUpWithGuidanceEmbed: parameters.advanced.speedUpWithGuidanceEmbed,
      referenceImages: FamilyTraits.of(family).usesMoodboard ? references : 0)
  }
}
