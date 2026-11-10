import HubCore
import HubKit
import SwiftUI

/// The built-in Generation tab: the prompt card across the whole width, then the parameter
/// cards two per row, cards in a row as tall as the tallest (spec §7).
struct GenerationTabView: View {
  let controller: GenerationController
  let connection: DrawThingsConnection
  /// Opens the Control tab (the Input card sends there).
  let openControl: () -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: DS.groupGap) {
        PresetBar(controller: controller)
          .padding(.horizontal, DS.panelPadding)
        PromptCard(controller: controller)
        // Edit models work from the Control tab's pictures: they are shown here too.
        if controller.isEditModel() {
          InputCard(controller: controller, openControl: openControl)
        }
        DSCardRow {
          DimensionsCard(controller: controller)
          SeedBatchCard(controller: controller)
        }
        DSCardRow {
          SamplingCard(controller: controller)
          LoRACard(controller: controller, connection: connection)
        }
        VideoCardsRow(controller: controller)
        AdvancedSection(controller: controller, connection: connection)
      }
      .padding(.bottom, DS.groupGap)
    }
    .scrollIndicators(.automatic)
  }
}

/// The video cards, after Sampling/LoRA and before the Advanced switch; nothing for an image model.
private struct VideoCardsRow: View {
  let controller: GenerationController

  var body: some View {
    let rows = VideoCardRows(
      model: controller.selectedModel(), sampler: controller.parameters.sampler)
    if rows.showsVideoCard {
      DSCardRow {
        VideoSettingsCard(controller: controller)
        if rows.showsAccelerators {
          AcceleratorCard(controller: controller)
        } else {
          Color.clear
        }
      }
    }
  }
}
