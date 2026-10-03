import HubCore
import HubKit
import SwiftUI

/// The words for what plug-ins contribute: field names, values, the pop-up of a conflict.
enum ContributionText {
  /// The name the field has in its card.
  static func name(_ field: ContributionField) -> String {
    switch field {
    case .prompt: String(localized: "card.prompt")
    case .negativePrompt: String(localized: "card.prompt.negative")
    case .width: String(localized: "card.dimensions.width")
    case .height: String(localized: "card.dimensions.height")
    case .steps: String(localized: "card.sampling.steps")
    case .guidanceScale: String(localized: "card.sampling.guidance")
    case .cfgZeroStar: String(localized: "card.sampling.cfgZero")
    case .cfgZeroInitSteps: String(localized: "card.sampling.cfgZeroInitSteps")
    case .sampler: String(localized: "card.sampling.sampler")
    case .shift: String(localized: "card.sampling.shift")
    case .resolutionDependentShift: String(localized: "card.sampling.resolutionShift")
    case .seed: String(localized: "card.seed.value")
    case .randomSeed: String(localized: "card.seed.random")
    case .batchSize: String(localized: "card.batch.size")
    case .batchCount: String(localized: "card.batch.count")
    }
  }

  /// A value as the field shows it.
  static func value(_ value: FieldValue, for field: ContributionField) -> String {
    switch value {
    case .text(let text): text
    case .int(let number): field == .sampler ? (Sampler(rawValue: number)?.displayName ?? "\(number)") : String(number)
    case .double(let number): number.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    case .bool(let flag): String(localized: flag ? "contribution.on" : "contribution.off")
    }
  }

  static func subject(_ subject: ContributionConflict.Subject) -> String {
    switch subject {
    case .field(let field): name(field)
    case .startImage: String(localized: "contribution.startImage")
    case .pipeline: String(localized: "contribution.pipeline")
    }
  }

  /// "Alpha · 24": the plug-in and what it wants, the text of a button of the pop-up.
  static func choice(_ side: ContributionConflict.Side, subject: ContributionConflict.Subject, plugins: PluginRegistry) -> String {
    let plugin = plugins.entries.first { $0.id == side.pluginID }?.name ?? side.pluginID
    let content: String =
      switch side.content {
      case .value(let value):
        if case .field(let field) = subject { Self.value(value, for: field) } else { "" }
      case .image(let name): name
      case .passes(let count): passes(count)
      }
    return "\(plugin) · \(content)"
  }

  static func passes(_ count: Int) -> String { String(format: String(localized: "contribution.passes"), count) }

  /// "Run · 2 passes".
  static func runTitle(passes count: Int) -> String {
    String(format: String(localized: "header.run.pipeline"), count)
  }

  /// The tooltip of the Run button with a pipeline: who proposed it and the passes.
  static func pipelineHelp(_ contribution: PipelineContribution, plugins: PluginRegistry) -> String {
    let plugin = plugins.entries.first { $0.id == contribution.pluginID }?.name ?? contribution.pluginID
    let list = contribution.pipeline.steps.enumerated().map { index, step in
      "\(index + 1). " + (step.title.isEmpty ? String(format: String(localized: "contribution.pass"), index + 1) : step.title)
    }
    return ([plugin + (contribution.pipeline.name.isEmpty ? "" : " · " + contribution.pipeline.name)] + list).joined(separator: "\n")
  }
}
