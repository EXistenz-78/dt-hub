import HubCore
import HubKit
import SwiftUI

/// The Advanced cards behind a switch (decided with the user, 1 October 2026): off, only the
/// switch and how many advanced values are changed; on, the cards that apply to the chosen
/// model, two per row, and a warning for changed values the model does not use (spec §6).
struct AdvancedSection: View {
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection

  private var model: CatalogModel? { controller.selectedModel(in: connection) }
  private var advanced: AdvancedParameters { controller.parameters.advanced }
  private var isOn: Binding<Bool> { controller.cards.binding("advanced", default: false) }

  private var visibleCards: [AdvancedCard] {
    AdvancedCard.allCases.filter { card in
      card.fields.contains { $0.isShown(for: model, sampler: controller.parameters.sampler) }
    }
  }

  var body: some View {
    VStack(spacing: DS.groupGap) {
      HStack(spacing: DS.controlGap) {
        Toggle(isOn: isOn) {
          Text("advanced.show")
        }
        .toggleStyle(DSCheckboxToggleStyle())
        let modified = advanced.modifiedFields.count
        if !isOn.wrappedValue, modified > 0 {
          Text(String(format: String(localized: "advanced.modifiedCount"), modified))
            .font(.caption)
            .foregroundStyle(DS.accent)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, DS.panelPadding)

      if isOn.wrappedValue {
        hiddenValuesWarning
        let cards = visibleCards
        ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { index in
          DSCardRow {
            AdvancedCardView(card: cards[index], controller: controller, connection: connection)
            if index + 1 < cards.count {
              AdvancedCardView(card: cards[index + 1], controller: controller, connection: connection)
            } else {
              Color.clear
            }
          }
        }
      }
    }
  }

  /// Changed values the chosen model does not use: kept, not sent, one click to reset.
  @ViewBuilder private var hiddenValuesWarning: some View {
    let hidden = advanced.hiddenModifiedFields(for: model, sampler: controller.parameters.sampler)
    if !hidden.isEmpty {
      HStack(alignment: .firstTextBaseline, spacing: DS.controlGap) {
        Image(systemName: "eye.slash")
          .foregroundStyle(DS.remove)
          .accessibilityHidden(true)
        Text(
          String(
            format: String(localized: "advanced.hidden"),
            hidden.map(\.title).formatted(.list(type: .and))))
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: DS.controlGap)
        Button {
          for field in hidden { controller.parameters.advanced.reset(field) }
        } label: {
          Text("advanced.hidden.reset")
        }
        .buttonStyle(DSPillButtonStyle())
      }
      .padding(DS.boxPadding)
      .background(
        RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
          .fill(DS.remove.opacity(0.10)))
      .overlay(
        RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
          .strokeBorder(DS.remove.opacity(0.35), lineWidth: 1))
    }
  }
}

extension AdvancedField {
  /// The field's name, for the hidden-values warning.
  var title: String {
    switch self {
    case .refiner: String(localized: "advanced.field.refiner")
    case .hiresFix: String(localized: "advanced.field.hiresFix")
    case .upscaler: String(localized: "advanced.field.upscaler")
    case .faceRestoration: String(localized: "advanced.field.faceRestoration")
    case .guidanceEmbed: String(localized: "advanced.field.guidanceEmbed")
    case .sharpness: String(localized: "advanced.field.sharpness")
    case .stochasticSamplingGamma: String(localized: "advanced.field.stochasticSamplingGamma")
    case .clipSkip: String(localized: "advanced.field.clipSkip")
    case .t5TextEncoder: String(localized: "advanced.field.t5TextEncoder")
    case .separateClipL: String(localized: "advanced.field.separateClipL")
    case .separateOpenClipG: String(localized: "advanced.field.separateOpenClipG")
    case .separateT5: String(localized: "advanced.field.separateT5")
    case .zeroNegativePrompt: String(localized: "advanced.field.zeroNegativePrompt")
    case .sdxlConditioning: String(localized: "advanced.field.sdxlConditioning")
    case .tiledDecoding: String(localized: "advanced.field.tiledDecoding")
    case .tiledDiffusion: String(localized: "advanced.field.tiledDiffusion")
    case .teaCache: String(localized: "advanced.field.teaCache")
    case .colorCalibration: String(localized: "advanced.field.colorCalibration")
    case .compressionArtifacts: String(localized: "advanced.field.compressionArtifacts")
    }
  }
}
