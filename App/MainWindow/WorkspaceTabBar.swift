import HubCore
import HubKit
import SwiftUI

/// The tab bar under the header: Generation, then one tab per active plug-in.
struct WorkspaceTabBar: View {
  let workspace: WorkspaceState

  var body: some View {
    HStack(spacing: DS.controlGap) {
      ForEach(workspace.tabs) { tab in
        Button {
          workspace.select(tab.id)
        } label: {
          HStack(spacing: DS.pillIconGap) {
            Image(systemName: tab.systemImage)
              .font(.system(size: 13, weight: .semibold))
            Text(tab.title)
          }
        }
        .buttonStyle(DSTabButtonStyle(isSelected: tab.id == workspace.selectedTabID))
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 4)
  }
}
