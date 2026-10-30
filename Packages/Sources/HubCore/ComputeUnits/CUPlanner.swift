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
  /// - Parameter strengthOfPass: what `GenerationController.runPipeline` sends as the strength of a pass: the step, whether
  ///   the pass replaces the tab's start image, whether its model is an edit model, and the pass's size (for the margins).
  public static func passes(
    fields: GenerationFields, model: CatalogModel?, control: CUControlSummary, pipeline: PluginPipeline?,
    presets: [String: Preset], catalog: ModelCatalog, headerModel: String?,
    strengthOfPass: (_ step: PipelineStep, _ replacesStart: Bool, _ editModel: Bool, _ width: Int, _ height: Int) -> Double
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
    // A pipeline the plug-in guides has no list: its passes are measured as the estimate it gave, `passes` times.
    let guided = pipeline.guided
    let listed = guided.map { [$0.estimate] } ?? pipeline.steps
    for (index, step) in listed.enumerated() {
      var used = PipelinePresets.fields(for: step, over: fields, presets: presets, catalog: catalog)
      if guided != nil, let size = step.size {
        used.parameters.width = size.width
        used.parameters.height = size.height
      }
      if step.usesPresetModel, let previousSize {
        let size = PipelineSizes.scaled(previousSize, by: step.scale, limit: used.parameters.sizeLimit)
        used.parameters.width = size.width
        used.parameters.height = size.height
      }
      previousSize = Size(width: used.parameters.width, height: used.parameters.height)
      let file = PipelinePresets.model(for: step, presets: presets, header: headerModel)
      let passModel = file.flatMap { catalog.model(forFile: $0) }
      let presetMissing = !step.preset.isEmpty && presets[step.preset] == nil
      let replacesStart = guided != nil || step.startImage != nil || (step.useOutputAsStart && index > 0)
      let hasImage = control.hasImage || replacesStart
      let strength = strengthOfPass(
        step, replacesStart, passModel?.capabilities.isEditModel ?? false, used.parameters.width, used.parameters.height)
      result.append(
        CUPass(
          title: step.title,
          inputs: presetMissing
            ? nil
            : inputs(
              used.parameters, model: passModel, hasImage: hasImage, strength: strength,
              references: step.moodboard?.count ?? control.moodboardCount)))
    }
    if let guided, let one = result.first { return Array(repeating: one, count: guided.passes) }
    return result
  }

  /// The presets the pipeline names that can be read, one by one: a missing or unreadable one does not take the
  /// others with it (`PipelinePresets.load` is all or nothing, which is right for a RUN but not for an estimate).
  public static func availablePresets(for pipeline: PluginPipeline, from store: PresetStore) -> [String: Preset] {
    var loaded: [String: Preset] = [:]
    for step in (pipeline.guided.map { [$0.estimate] } ?? pipeline.steps) where !step.preset.isEmpty && loaded[step.preset] == nil {
      if let preset = try? store.load(named: step.preset) { loaded[step.preset] = preset }
    }
    return loaded
  }

  static func inputs(
    _ parameters: GenerationParameters, model: CatalogModel?, hasImage: Bool, strength: Double, references: Int
  ) -> CUInputs? {
    guard let model, let family = model.family else { return nil }
    // Video (H3, LTX-2.3) is estimated with Draw Things' formula like any family: the frame count goes along. A video
    // family the estimator does not cover has no estimate (the meter shows a dash).
    return CUInputs(
      family: family, modelFile: model.file, capabilities: model.capabilities, width: parameters.width,
      height: parameters.height, steps: parameters.steps, strength: hasImage ? strength : 1,
      guidanceScale: parameters.guidanceScale, batchSize: parameters.batchSize, hasImage: hasImage,
      speedUpWithGuidanceEmbed: parameters.advanced.speedUpWithGuidanceEmbed,
      referenceImages: FamilyTraits.of(family).usesMoodboard ? references : 0,
      numFrames: VideoFamilies.keys.contains(family) ? parameters.video.numFrames : 1)
  }
}
