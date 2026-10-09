import HubKit

/// The presets a plug-in's pipeline names (`2026-10-04-preset-pipeline-design.md` §4, §8).
@MainActor
public enum PipelinePresets {
  /// What stops a pipeline before its first pass: the names the Preset menu does not have, and those whose
  /// file is not a preset.
  public struct Problem: Error, Equatable, Sendable {
    public var missing: [String]
    public var unreadable: [String]
  }

  /// Reads, once each, only the presets the pipeline names. They stay in memory for the whole Run, so a preset
  /// changed or deleted meanwhile changes nothing. The result is keyed by the name as the step wrote it.
  public static func load(_ pipeline: PluginPipeline, from store: PresetStore) -> Result<[String: Preset], Problem> {
    var loaded: [String: Preset] = [:]
    var problem = Problem(missing: [], unreadable: [])
    for step in pipeline.steps where !step.preset.isEmpty && loaded[step.preset] == nil {
      do {
        loaded[step.preset] = try store.load(named: step.preset)
      } catch {
        switch error {
        case .unreadable: if !problem.unreadable.contains(step.preset) { problem.unreadable.append(step.preset) }
        default: if !problem.missing.contains(step.preset) { problem.missing.append(step.preset) }
        }
      }
    }
    return problem.missing.isEmpty && problem.unreadable.isEmpty ? .success(loaded) : .failure(problem)
  }

  /// What a pass runs with: the tab's fields; then the pass's preset on them (its parameters, and its prompt and
  /// negative prompt when it has them, but not its model nor a size); then the pass's own `fields` (a size in them
  /// is ignored: a pass never changes the size); then its `loras`. The advanced values and the extras stay those of the
  /// tab, whatever `fields` says. A pass with nothing runs the tab's fields as they are.
  public static func fields(
    for step: PipelineStep, over tab: GenerationFields, presets: [String: Preset], catalog: ModelCatalog
  ) -> GenerationFields {
    var base = tab
    if !step.preset.isEmpty, let preset = presets[step.preset] {
      let load = PresetLoad.of(preset, current: tab, catalog: catalog)
      base = GenerationFields(prompt: load.prompt, negativePrompt: load.negativePrompt, parameters: load.parameters)
    }
    var result = step.fields.isEmpty ? base : step.fields.applied(to: base)
    result.parameters.width = base.parameters.width
    result.parameters.height = base.parameters.height
    result.parameters.loras = merged(base.parameters.loras, with: step.loras)
    return result
  }

  /// A LoRA of the step already on the card gets the step's weight (and its mode or trigger word when it gives a
  /// non-default one); a new one goes at the end.
  static func merged(_ current: [LoRASelection], with step: [LoRASelection]) -> [LoRASelection] {
    var result = current
    for lora in step {
      if let index = result.firstIndex(where: { $0.file == lora.file }) {
        result[index].weight = lora.weight
        if lora.mode != .all { result[index].mode = lora.mode }
        if !lora.trigger.isEmpty { result[index].trigger = lora.trigger }
      } else {
        result.append(lora)
      }
    }
    return result
  }
}
