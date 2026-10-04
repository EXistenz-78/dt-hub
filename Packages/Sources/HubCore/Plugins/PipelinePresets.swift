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

  /// What a pass runs with: the tab's fields with the pass's preset on them (its parameters, and its prompt
  /// and negative prompt when it has them), but not its model nor a size. A pass without a preset runs the
  /// tab's fields as they are.
  public static func fields(
    for step: PipelineStep, over tab: GenerationFields, presets: [String: Preset], catalog: ModelCatalog
  ) -> GenerationFields {
    guard !step.preset.isEmpty, let preset = presets[step.preset] else { return tab }
    let load = PresetLoad.of(preset, current: tab, catalog: catalog)
    return GenerationFields(prompt: load.prompt, negativePrompt: load.negativePrompt, parameters: load.parameters)
  }
}
