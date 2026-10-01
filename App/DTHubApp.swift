import AppKit
import HubCore
import HubKit
import LLMBridge
import SwiftUI

@main
struct DTHubApp: App {
  @State private var workspace = WorkspaceState(
    generationTab: WorkspaceTab(
      id: WorkspaceTab.generationID,
      title: String(localized: "tab.generation"),
      systemImage: "slider.horizontal.3"))
  @State private var connection: DrawThingsConnection
  @State private var languageModel: LanguageModelManager
  @State private var generation: GenerationController

  init() {
    let connection = DrawThingsConnection()
    // The language model frees the managed server's memory when the settings ask for it.
    let languageModel = LanguageModelManager(
      service: MLXLanguageModelService(), releaseImageModel: { await connection.releaseImageModel() })
    _connection = State(initialValue: connection)
    _languageModel = State(initialValue: languageModel)
    _generation = State(initialValue: GenerationController(languageModel: languageModel))
  }

  var body: some Scene {
    WindowGroup(String(localized: "app.title")) {
      MainWindowView(workspace: workspace, connection: connection, generation: generation)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
          generation.saveSessionNow()
        }
    }
    .windowResizability(.contentMinSize)
    .commands {
      CommandMenu(String(localized: "tab.generation")) {
        GenerationCommands(generation: generation, connection: connection)
      }
    }

    Window(String(localized: "results.title"), id: ResultsWindow.id) {
      ResultsView(controller: generation, connection: connection)
    }
    .windowResizability(.contentMinSize)

    Settings {
      PreferencesView(connection: connection, generation: generation, languageModel: languageModel)
    }
  }
}
