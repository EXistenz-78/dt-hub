import HubKit
import SwiftUI

/// The built-in Generation tab: the prompt card across the whole width, then the parameter
/// cards two per row, cards in a row as tall as the tallest (spec §7).
struct GenerationTabView: View {
  let controller: GenerationController

  var body: some View {
    ScrollView {
      VStack(spacing: DS.groupGap) {
        PromptCard(controller: controller)
        DSCardRow {
          DimensionsCard(controller: controller)
          SeedBatchCard(controller: controller)
        }
        DSCardRow {
          SamplingCard(controller: controller)
          Color.clear
        }
      }
      .padding(.bottom, DS.groupGap)
    }
    .scrollIndicators(.automatic)
  }
}
