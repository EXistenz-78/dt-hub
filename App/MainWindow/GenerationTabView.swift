import HubKit
import SwiftUI

/// The built-in Generation tab: the prompt card across the whole width, then the parameter
/// cards two per row, cards in a row as tall as the tallest (spec §7).
struct GenerationTabView: View {
  let controller: GenerationController
  let connection: DrawThingsConnection

  var body: some View {
    ScrollView {
      VStack(spacing: DS.groupGap) {
        PresetBar(controller: controller, connection: connection)
          .padding(.horizontal, DS.panelPadding)
        PromptCard(controller: controller, connection: connection)
        DSCardRow {
          DimensionsCard(controller: controller)
          SeedBatchCard(controller: controller)
        }
        DSCardRow {
          SamplingCard(controller: controller, connection: connection)
          LoRACard(controller: controller, connection: connection)
        }
        AdvancedSection(controller: controller, connection: connection)
      }
      .padding(.bottom, DS.groupGap)
    }
    .scrollIndicators(.automatic)
  }
}
