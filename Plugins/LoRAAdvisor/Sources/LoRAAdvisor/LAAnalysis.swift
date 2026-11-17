import DTHubPluginKit
import Foundation

/// What the analysis of a LoRA's page changes, by the rules of spec §4 and §5: pure, so the job only carries it out.
struct LAAnalysisPlan: Equatable {
  /// The most characters the stored summary has (the prompt asks for about 60 words).
  static let maxNotes = 1200

  /// The new notes; nil leaves them as they are.
  var notes: String?
  /// What goes to the app's LoRA data; every value is `.keep` when there is nothing to write. The trigger is never in it.
  var settings: DTHubLoRASettings
  /// The weights to write; nil when they are not to be touched.
  var weights: LAWeights.Values?
  /// The trigger the page suggests, for the user to confirm; nil when there is none to offer.
  var triggerProposal: String?

  /// `lora` is the LoRA as the app has it now, `entry` the plug-in's data; `replaceNotes` is true for a LoRA whose notes
  /// are still the raw text of its page.
  static func make(analysis: LASummary.Analysis, lora: DTHubCatalogLoRA, entry: LAEntry, replaceNotes: Bool) -> LAAnalysisPlan {
    var plan = LAAnalysisPlan(notes: nil, settings: DTHubLoRASettings(), weights: nil, triggerProposal: nil)

    if replaceNotes, let summary = analysis.summary, !summary.isEmpty { plan.notes = String(summary.prefix(maxNotes)) }

    var category = LACategory(raw: lora.category)
    if !entry.categoryManual, let found = analysis.category {
      category = found
      plan.settings.category = .set(found.rawValue)
    }

    if !entry.paramsManual, category == .turbo {
      if let steps = analysis.steps { plan.settings.steps = .set(steps) }
      if let guidance = analysis.guidance { plan.settings.guidance = .set(guidance) }
      if let shift = analysis.shift { plan.settings.shift = .set(shift) }
    }

    let untouched = lora.minWeight == nil && lora.maxWeight == nil && lora.weight == LAWeights.defaultBase
    if untouched, analysis.min != nil || analysis.base != nil || analysis.max != nil {
      plan.weights = LAWeights.normalised(min: analysis.min, base: analysis.base, max: analysis.max)
    }

    if let found = LATriggers.proposal(current: lora.trigger, found: analysis.triggers),
      entry.triggerDismissed.map({ LATriggers.words($0) != LATriggers.words(found) }) ?? true
    {
      plan.triggerProposal = found
    }
    return plan
  }
}
