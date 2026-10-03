import AppKit
import HubCore
import HubKit
import LLMBridge
import PluginHost
import SwiftUI

@main
struct DTHubApp: App {
  @State private var workspace = WorkspaceState(
    controlTab: WorkspaceTab(
      id: WorkspaceTab.controlID,
      title: String(localized: "tab.control"),
      systemImage: "photo.on.rectangle"),
    generationTab: WorkspaceTab(
      id: WorkspaceTab.generationID,
      title: String(localized: "tab.generation"),
      systemImage: "slider.horizontal.3"))
  @State private var connection: DrawThingsConnection
  @State private var languageModel: LanguageModelManager
  @State private var generation: GenerationController
  @State private var download: LanguageModelDownloadController
  @State private var plugins: PluginRegistry

  init() {
    let connection = DrawThingsConnection()
    // The language model frees the managed server's memory when the settings ask for it.
    let languageModel = LanguageModelManager(
      service: MLXLanguageModelService(), releaseImageModel: { await connection.releaseImageModel() },
      isImageModelBusy: { connection.isImageWorkActive() })
    let control = ControlStore(
      storage: FileReferenceStorage(folder: FileReferenceStorage.defaultFolder), fileURL: ControlStore.defaultFileURL)
    let generation = GenerationController(languageModel: languageModel, control: control)
    // The language model never takes the image model's memory while an image is being made.
    connection.isImageWorkActive = { generation.session.isRunning || generation.isPreparing }
    _connection = State(initialValue: connection)
    _languageModel = State(initialValue: languageModel)
    _generation = State(initialValue: generation)
    _download = State(initialValue: LanguageModelDownloadController(downloader: HubLanguageModelDownloader()))
    // Plug-ins load now; holding ⌥ at launch loads none (plug-in design §5).
    let plugins = PluginRegistry(
      folder: PluginFolder(root: PluginFolder.defaultRoot),
      settings: PluginSettingsStore(fileURL: PluginSettingsStore.defaultFileURL), loader: BundlePluginLoader(),
      tempFolder: FileManager.default.temporaryDirectory.appendingPathComponent("DTHub-plugins", isDirectory: true))
    plugins.start(skipping: NSEvent.modifierFlags.contains(.option))
    _plugins = State(initialValue: plugins)
    // A download cut short by quitting leaves a hidden folder with part of a model: remove it.
    let leftovers = URL(fileURLWithPath: languageModel.settings.folder, isDirectory: true)
      .appendingPathComponent(RecommendedLanguageModel.folderName, isDirectory: true).deletingLastPathComponent()
    Task.detached { HubLanguageModelDownloader.removeLeftoverStaging(in: leftovers) }
  }

  var body: some Scene {
    WindowGroup(String(localized: "app.title")) {
      MainWindowView(workspace: workspace, connection: connection, generation: generation, plugins: plugins)
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
      PreferencesView(
        connection: connection, generation: generation, languageModel: languageModel, download: download,
        plugins: plugins)
    }
  }
}
