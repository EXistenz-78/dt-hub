import HubKit
import SwiftUI

/// Steps, text guidance with CFG-Zero*, sampler, shift with resolution-dependent shift (spec §6).
struct SamplingCard: View {
  @Bindable var controller: GenerationController

  var body: some View {
    DSCollapsibleCard(
      String(localized: "card.sampling"), systemImage: "dial.medium",
      isExpanded: controller.cards.binding("sampling")
    ) {
      VStack(spacing: DS.rowGap) {
        CardRow(label: String(localized: "card.sampling.steps")) {
          IntField(
            label: String(localized: "card.sampling.steps"), value: $controller.parameters.steps,
            range: GenerationParameters.stepsRange)
        }

        CardRow(label: String(localized: "card.sampling.guidance")) {
          Toggle(isOn: $controller.parameters.cfgZeroStar) {
            Text("card.sampling.cfgZero")
          }
          .toggleStyle(DSCheckboxToggleStyle())
        } control: {
          DecimalField(
            label: String(localized: "card.sampling.guidance"), value: $controller.parameters.guidanceScale,
            range: GenerationParameters.guidanceRange, step: 0.5)
        }
        if controller.parameters.cfgZeroStar {
          CardRow(label: String(localized: "card.sampling.cfgZeroInitSteps")) {
            IntField(
              label: String(localized: "card.sampling.cfgZeroInitSteps"),
              value: $controller.parameters.cfgZeroInitSteps,
              range: 0...controller.parameters.steps)
          }
        }

        CardRow(label: String(localized: "card.sampling.sampler")) {
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

        CardRow(label: String(localized: "card.sampling.shift")) {
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
    }
  }
}
