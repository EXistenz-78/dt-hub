import HubKit
import SwiftUI

/// Steps, text guidance with CFG-Zero*, sampler, shift with resolution-dependent shift (spec §6).
/// Shift, "resolution-based" and CFG-Zero* show only for flow-matching families (`FamilyTraits`).
struct SamplingCard: View {
  @Bindable var controller: GenerationController

  var body: some View {
    DSCollapsibleCard(
      String(localized: "card.sampling"), systemImage: "dial.medium",
      isExpanded: controller.cards.binding("sampling")
    ) {
      let usesShift = controller.traits().usesShift
      VStack(spacing: DS.rowGap) {
        CardRow(label: String(localized: "card.sampling.steps"), fields: [.steps]) {
          IntField(
            label: String(localized: "card.sampling.steps"), value: $controller.parameters.steps,
            range: GenerationParameters.stepsRange)
        }

        CardRow(label: String(localized: "card.sampling.guidance"), fields: [.guidanceScale, .cfgZeroStar]) {
          if usesShift {
            Toggle(isOn: $controller.parameters.cfgZeroStar) {
              Text("card.sampling.cfgZero")
            }
            .toggleStyle(DSCheckboxToggleStyle())
          }
        } control: {
          DecimalField(
            label: String(localized: "card.sampling.guidance"), value: $controller.parameters.guidanceScale,
            range: GenerationParameters.guidanceRange, step: 0.5)
        }
        if usesShift, controller.parameters.cfgZeroStar {
          CardRow(label: String(localized: "card.sampling.cfgZeroInitSteps"), fields: [.cfgZeroInitSteps]) {
            IntField(
              label: String(localized: "card.sampling.cfgZeroInitSteps"),
              value: $controller.parameters.cfgZeroInitSteps,
              range: 0...controller.parameters.steps)
          }
        }

        CardRow(label: String(localized: "card.sampling.sampler"), fields: [.sampler]) {
          Picker(selection: $controller.parameters.sampler) {
            ForEach(Sampler.allCases) { sampler in
              Text(verbatim: sampler.displayName).tag(sampler)
            }
          } label: {
            EmptyView()
          }
          .labelsHidden()
          .fixedSize()
          .accessibilityLabel(String(localized: "card.sampling.sampler"))
        }

        if usesShift {
          CardRow(label: String(localized: "card.sampling.shift"), fields: [.shift, .resolutionDependentShift]) {
            Toggle(isOn: $controller.parameters.resolutionDependentShift) {
              Text("card.sampling.resolutionShift")
            }
            .toggleStyle(DSCheckboxToggleStyle())
          } control: {
            DecimalField(
              label: String(localized: "card.sampling.shift"), value: $controller.parameters.shift,
              range: GenerationParameters.shiftRange, step: 0.1, fractionDigits: 2)
              .disabled(controller.parameters.resolutionDependentShift)
          }
        }

        defaultsRow
      }
    }
  }

  /// The line about the last save or reset of the model's default, or a LoRA of it that is missing (the buttons are in
  /// the Generation tab's bar).
  @ViewBuilder private var defaultsRow: some View {
    if let notice = controller.defaultsNotice {
      Text(verbatim: notice)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
