import Foundation
import HubKit

/// Picks the LLM for a prompt button from the assignments of Settings › LLM (pure logic).
public enum LanguageModelRouter {
  /// The model for `task` on `family`: the first by name assigned to that family with a use that
  /// covers the task; else the first on "all others". A Generate task needs a model that reads
  /// images. `family == nil` (catalog not loaded) skips the family step.
  public static func model(
    for task: LanguageModelTask, family: String?, models: [LanguageModelDescriptor],
    assignments: [String: LanguageModelAssignment]
  ) -> Result<LanguageModelDescriptor, LanguageModelError> {
    var rejectedForImages = false
    func first(_ wanted: LanguageModelFamily) -> LanguageModelDescriptor? {
      for model in sorted(models) {
        guard let assignment = assignments[model.name], assignment.family == wanted, assignment.use.covers(task)
        else { continue }
        if task == .describe, !model.supportsImages {
          rejectedForImages = true
          continue
        }
        return model
      }
      return nil
    }
    if let family, let found = first(.family(family)) { return .success(found) }
    if let found = first(.allOthers) { return .success(found) }
    return .failure(rejectedForImages ? .imagesNotSupported : .noModelSelected)
  }

  /// The names of the models that never win at any place (family + task) where they are assigned:
  /// another model takes precedence.
  public static func shadowed(
    models: [LanguageModelDescriptor], assignments: [String: LanguageModelAssignment]
  ) -> Set<String> {
    var result: Set<String> = []
    for model in models {
      guard let assignment = assignments[model.name], assignment.family != .none, assignment.use != .pluginsOnly
      else { continue }
      let family: String? = if case .family(let key) = assignment.family { key } else { nil }
      let wins = [LanguageModelTask.enhance, .describe].contains { task in
        guard assignment.use.covers(task), task == .enhance || model.supportsImages else { return false }
        // For "all others" ask with no family: only the all-others step runs.
        guard case .success(let chosen) = self.model(for: task, family: family, models: models, assignments: assignments)
        else { return false }
        return chosen.name == model.name
      }
      if !wins { result.insert(model.name) }
    }
    return result
  }

  private static func sorted(_ models: [LanguageModelDescriptor]) -> [LanguageModelDescriptor] {
    models.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}
