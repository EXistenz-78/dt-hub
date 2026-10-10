import HubKit
import SwiftUI

/// Width and height in multiples of 64, aspect ratios, swap, ratio lock (spec §6).
struct DimensionsCard: View {
  @Bindable var controller: GenerationController

  var body: some View {
    DSCollapsibleCard(
      String(localized: "card.dimensions"), systemImage: "aspectratio",
      isExpanded: controller.cards.binding("dimensions")
    ) {
      VStack(spacing: DS.rowGap) {
        CardRow(label: String(localized: "card.dimensions.width"), fields: [.width]) {
          IntField(
            label: String(localized: "card.dimensions.width"),
            value: Binding(
              get: { controller.parameters.width },
              set: { controller.parameters.setWidth($0, keepingRatio: controller.lockedRatio) }),
            range: GenerationParameters.sizeRange.lowerBound...controller.parameters.sizeLimit, step: 64,
            commit: { GenerationParameters.snap(Double($0), limit: controller.parameters.sizeLimit) })
        }
        CardRow(label: String(localized: "card.dimensions.height"), fields: [.height]) {
          IntField(
            label: String(localized: "card.dimensions.height"),
            value: Binding(
              get: { controller.parameters.height },
              set: { controller.parameters.setHeight($0, keepingRatio: controller.lockedRatio) }),
            range: GenerationParameters.sizeRange.lowerBound...controller.parameters.sizeLimit, step: 64,
            commit: { GenerationParameters.snap(Double($0), limit: controller.parameters.sizeLimit) })
        }
        HStack(spacing: DS.controlGap) {
          Menu {
            ForEach(AspectRatio.presets, id: \.self) { ratio in
              Button {
                controller.apply(ratio)
              } label: {
                Text(verbatim: ratio.label)
              }
            }
          } label: {
            DSMenuLabel(String(localized: "card.dimensions.presets"), systemImage: "rectangle.ratio.4.to.3")
          }
          .dsMenuPill()
          Button {
            controller.swapDimensions()
          } label: {
            Image(systemName: "arrow.left.arrow.right")
          }
          .buttonStyle(DSGlassCircleButtonStyle())
          .help(String(localized: "card.dimensions.swap"))
          .accessibilityLabel(String(localized: "card.dimensions.swap"))
          VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $controller.lockRatio) {
              Text("card.dimensions.lockRatio")
            }
            .toggleStyle(DSCheckboxToggleStyle())
            Toggle(
              isOn: Binding(
                get: { controller.parameters.isHighRes }, set: { controller.setHighRes($0) })
            ) { Text("card.dimensions.highRes") }
              .toggleStyle(DSCheckboxToggleStyle())
              .disabled(controller.parameters.advanced.tiledDiffusion)
              .help(String(localized: "card.dimensions.highRes.help"))
          }
          .padding(.leading, 4)
          Spacer(minLength: 0)
        }
      }
    }
  }
}
