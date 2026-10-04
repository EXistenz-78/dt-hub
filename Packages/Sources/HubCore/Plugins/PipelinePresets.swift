import HubKit

/// The presets a plug-in's pipeline names (`2026-10-04-preset-pipeline-design.md` §4).
@MainActor
public enum PipelinePresets {
  /// The names the pipeline asks for that the Preset menu does not have, once each, in order.
  public static func missing(in pipeline: PluginPipeline, store: PresetStore) -> [String] {
    var result: [String] = []
    for step in pipeline.steps where !step.preset.isEmpty {
      if store.preset(named: step.preset) == nil, !result.contains(step.preset) { result.append(step.preset) }
    }
    return result
  }

  /// What a pass runs with: the tab's fields with the pass's preset on them (its parameters, and its prompt
  /// and negative prompt when it has them), but not its model nor a size. A pass without a preset, or whose
  /// preset is gone, runs the tab's fields as they are.
  public static func fields(for step: PipelineStep, over tab: GenerationFields, store: PresetStore, catalog: ModelCatalog)
    -> GenerationFields
  {
    guard !step.preset.isEmpty, let preset = store.preset(named: step.preset) else { return tab }
    let load = PresetLoad.of(preset, current: tab, catalog: catalog)
    return GenerationFields(prompt: load.prompt, negativePrompt: load.negativePrompt, parameters: load.parameters)
  }
}
