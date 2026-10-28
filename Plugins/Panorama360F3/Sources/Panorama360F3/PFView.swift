import DTHubDesign
import SwiftUI

/// The tab, in the look of the app: the Moodboard and the Prompt side by side.
struct PFView: View {
  @ObservedObject var state: PFState
  var actions: PFViewActions = .none

  var body: some View {
    ScrollView { content }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// What the tab scrolls (the tests draw this, a scroll view does not render to an image).
  var content: some View {
    VStack(spacing: DS.groupGap) {
      HStack(alignment: .top, spacing: DS.groupGap) {
        PFMoodboardCard(state: state).frame(maxWidth: .infinity)
        PFPromptCard(state: state, actions: actions).frame(maxWidth: .infinity)
      }
    }
    .padding(DS.groupGap)
  }
}
