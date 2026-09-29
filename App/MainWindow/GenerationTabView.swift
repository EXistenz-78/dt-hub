import HubKit
import SwiftUI

/// The built-in Generation tab. Empty in M1: the prompt and parameter cards
/// are added one by one from M3 (spec §15).
struct GenerationTabView: View {
  var body: some View {
    ContentUnavailableView(
      "generation.empty.title",
      systemImage: "slider.horizontal.3",
      description: Text("generation.empty.message"))
  }
}
