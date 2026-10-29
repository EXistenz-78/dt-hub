import HubCore
import HubKit
import SwiftUI

/// Sol Attention and TeaCache for the video families that use accelerators (H3); both off by default.
struct AcceleratorCard: View {
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection

  var body: some View {
    let rows = VideoCardRows(
      model: controller.selectedModel(in: connection), sampler: controller.parameters.sampler)
    if rows.showsAccelerators {
      DSCollapsibleCard(
        String(localized: "card.accelerators"), systemImage: "bolt",
        isExpanded: controller.cards.binding("accelerators")
      ) {
        VStack(alignment: .leading, spacing: DS.rowGap) {
          solAttention
          teaCache
        }
      }
    }
  }

  private func toggleRow(_ title: String, help: String, isOn: Binding<Bool>) -> some View {
    HStack(spacing: DS.controlGap) {
      Toggle(isOn: isOn) { Text(verbatim: title) }
        .toggleStyle(DSCheckboxToggleStyle())
      Image(systemName: "info.circle")
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
      Spacer(minLength: 0)
    }
  }

  @ViewBuilder private var solAttention: some View {
    let video = $controller.parameters.video
    toggleRow(
      String(localized: "card.accelerators.sol"), help: String(localized: "card.accelerators.sol.help"),
      isOn: video.usesSolAttention)
    if video.wrappedValue.usesSolAttention {
      CardRow(label: String(localized: "card.accelerators.sol.start")) {
        IntField(
          label: String(localized: "card.accelerators.sol.start"), value: video.solAttentionStart,
          range: VideoParameters.solStartRange)
      }
      CardRow(label: String(localized: "card.accelerators.sol.tau")) {
        DecimalField(
          label: String(localized: "card.accelerators.sol.tau"), value: video.solAttentionTau,
          range: VideoParameters.solTauRange, step: 0.1, fractionDigits: 2)
      }
    }
  }

  @ViewBuilder private var teaCache: some View {
    let advanced = $controller.parameters.advanced
    toggleRow(
      String(localized: "card.accelerators.teacache"), help: String(localized: "card.accelerators.teacache.help"),
      isOn: advanced.teaCache)
    if advanced.wrappedValue.teaCache {
      CardRow(label: String(localized: "card.accelerators.teacache.start")) {
        IntField(
          label: String(localized: "card.accelerators.teacache.start"), value: advanced.teaCacheStart,
          range: AdvancedParameters.teaCacheStepRange)
      }
      CardRow(label: String(localized: "card.accelerators.teacache.end")) {
        IntField(
          label: String(localized: "card.accelerators.teacache.end"), value: advanced.teaCacheEnd,
          range: AdvancedParameters.teaCacheEndRange)
      }
      CardRow(label: String(localized: "card.accelerators.teacache.threshold")) {
        DecimalField(
          label: String(localized: "card.accelerators.teacache.threshold"), value: advanced.teaCacheThreshold,
          range: AdvancedParameters.unitRange, step: 0.01, fractionDigits: 2)
      }
      CardRow(label: String(localized: "card.accelerators.teacache.skip")) {
        IntField(
          label: String(localized: "card.accelerators.teacache.skip"), value: advanced.teaCacheMaxSkipSteps,
          range: AdvancedParameters.teaCacheSkipRange)
      }
    }
  }
}
