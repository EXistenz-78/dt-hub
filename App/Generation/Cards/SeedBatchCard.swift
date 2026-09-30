import HubKit
import SwiftUI

/// Seed (random or fixed) and batch (spec §6).
struct SeedBatchCard: View {
  @Bindable var controller: GenerationController
  /// The seed as typed, read on every keystroke.
  @State private var seedText = ""
  @FocusState private var seedFocused: Bool

  var body: some View {
    DSCollapsibleCard(
      String(localized: "card.seed"), systemImage: "dice",
      isExpanded: controller.cards.binding("seed")
    ) {
      VStack(spacing: DS.rowGap) {
        CardRow(label: String(localized: "card.seed.value")) {
          Toggle(isOn: $controller.parameters.randomSeed) {
            Text("card.seed.random")
          }
          .toggleStyle(DSCheckboxToggleStyle())
        } control: {
          HStack(spacing: DS.controlGap) {
            TextField(String(localized: "card.seed.value"), text: $seedText)
              .labelsHidden()
              .textFieldStyle(.roundedBorder)
              .monospacedDigit()
              .multilineTextAlignment(.trailing)
              .frame(width: 120)
              .focused($seedFocused)
              .disabled(controller.parameters.randomSeed)
              .onChange(of: seedText) {
                if let seed = UInt32(seedText.trimmingCharacters(in: .whitespaces)) {
                  controller.parameters.seed = seed
                }
              }
            Button {
              controller.parameters.seed = UInt32.random(in: .min ... .max)
              controller.parameters.randomSeed = false
            } label: {
              Image(systemName: "dice")
            }
            .buttonStyle(DSGlassCircleButtonStyle())
            .help(String(localized: "card.seed.roll"))
            .accessibilityLabel(String(localized: "card.seed.roll"))
          }
        }

        CardRow(label: String(localized: "card.batch.size")) {
          IntField(
            label: String(localized: "card.batch.size"), value: $controller.parameters.batchSize,
            range: GenerationParameters.batchSizeRange)
        }
        CardRow(label: String(localized: "card.batch.count")) {
          IntField(
            label: String(localized: "card.batch.count"), value: $controller.parameters.batchCount,
            range: GenerationParameters.batchCountRange)
        }
      }
    }
    .onAppear { seedText = String(controller.parameters.seed) }
    .onChange(of: controller.parameters.seed) { if !seedFocused { seedText = String(controller.parameters.seed) } }
  }
}
