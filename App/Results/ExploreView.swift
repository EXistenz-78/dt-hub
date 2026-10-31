import HubCore
import SwiftUI

/// The Explore tab: every picture of every project in one grid (filled in by the next tasks).
struct ExploreView: View {
  let controller: GenerationController
  let connection: DrawThingsConnection

  var body: some View {
    Text("results.tab.explore")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
