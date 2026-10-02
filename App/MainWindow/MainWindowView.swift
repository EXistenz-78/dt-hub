import HubCore
import HubKit
import SwiftUI

/// Header, tab bar, and the content of the selected tab (spec §7).
struct MainWindowView: View {
  let workspace: WorkspaceState
  let connection: DrawThingsConnection
  let generation: GenerationController

  var body: some View {
    VStack(spacing: DS.panelPadding) {
      HeaderBar(connection: connection, generation: generation)
      ManagedServerBanner(connection: connection)
      DSTabFrame {
        WorkspaceTabBar(workspace: workspace)
      } content: {
        tabContent
      }
    }
    .padding(20)
    .frame(minWidth: 900, idealWidth: 1100, minHeight: 640, idealHeight: 820)
    .background(DSBackground())
    .background(DSWindowConfigurator())
    .tint(DS.accent)
  }

  @ViewBuilder private var tabContent: some View {
    if workspace.selectedTabID == WorkspaceTab.controlID {
      ControlTabView(generation: generation, connection: connection)
    } else if workspace.selectedTabID == WorkspaceTab.generationID {
      GenerationTabView(controller: generation, connection: connection)
    } else {
      // Plug-in tabs arrive with the plug-in contract (M7).
      EmptyView()
    }
  }
}
