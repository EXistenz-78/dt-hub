import Foundation
import HubKit

/// Picks the LLM for a prompt button from the assignments of Settings › LLM (pure logic).
public enum LanguageModelRouter {
  /// The model for `task` on `family`: the first by name assigned to that family with a use that
  /// covers the task; else the first on "all others". A Generate task needs a model that reads
  /// images, and so does any task with `needs.needsImages` (Enhance with pictures attached). `family == nil` (catalog not loaded) skips the family step.
  public static func model(
    for task: LanguageModelTask, family: String?, models: [LanguageModelDescriptor],
    assignments: [String: LanguageModelAssignment], needs: LanguageModelNeeds = LanguageModelNeeds()
  ) -> Result<LanguageModelDescriptor, LanguageModelError> {
    var rejectedForImages = false
    func first(_ wanted: LanguageModelFamily) -> LanguageModelDescriptor? {
      for model in sorted(models) {
        guard let assignment = assignments[model.name], assignment.family == wanted, assignment.use.covers(task, controlHasImages: needs.controlHasImages)
        else { continue }
        if task == .describe || needs.needsImages, !model.supportsImages {
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

  /// The names of the models that never win at any place (family + situation) where they are assigned: another model
  /// takes precedence. The situations are Enhance with an empty Control, Enhance with pictures (needing vision only if
  /// the model reads them) and Generate; a model counts as winning if it wins in one its use covers.
  public static func shadowed(
    models: [LanguageModelDescriptor], assignments: [String: LanguageModelAssignment]
  ) -> Set<String> {
    var result: Set<String> = []
    for model in models {
      guard let assignment = assignments[model.name], assignment.family != .none, assignment.use != .pluginsOnly
      else { continue }
      let family: String? = if case .family(let key) = assignment.family { key } else { nil }
      let situations: [(LanguageModelTask, LanguageModelNeeds)] = [
        (.enhance, LanguageModelNeeds(controlHasImages: false, needsImages: false)),
        (.enhance, LanguageModelNeeds(controlHasImages: true, needsImages: model.supportsImages)),
        (.describe, LanguageModelNeeds(controlHasImages: true, needsImages: true)),
      ]
      let wins = situations.contains { task, needs in
        guard assignment.use.covers(task, controlHasImages: needs.controlHasImages) else { return false }
        if task == .describe, !model.supportsImages { return false }
        // For "all others" ask with no family: only the all-others step runs.
        guard
          case .success(let chosen) = self.model(
            for: task, family: family, models: models, assignments: assignments, needs: needs)
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
