import HubCore
import HubKit
import SwiftUI

@main
struct DTHubApp: App {
  @State private var workspace = WorkspaceState(
    generationTab: WorkspaceTab(
      id: WorkspaceTab.generationID,
      title: String(localized: "tab.generation"),
      systemImage: "slider.horizontal.3"))
  @State private var connection = DrawThingsConnection()

  var body: some Scene {
    WindowGroup(String(localized: "app.title")) {
      MainWindowView(workspace: workspace, connection: connection)
    }
    .windowResizability(.contentMinSize)

    Settings {
      PreferencesView(connection: connection)
    }
  }
}
