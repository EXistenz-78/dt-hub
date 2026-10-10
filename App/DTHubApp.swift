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
  @State private var projects: ProjectManager
  @State private var canvasWindow = CanvasWindowState()

  init() {
    let connection = DrawThingsConnection()
    // The user's own LoRA trigger words and weights: read now, written at every change (`loras.json`).
    let loraStore = LoRAOverridesStore(fileURL: LoRAOverridesStore.defaultFileURL)
    connection.monitor.loraOverrides = loraStore.load()
    connection.monitor.saveLoRAOverrides = { loraStore.save($0) }
    // The language model frees the managed server's memory when the settings ask for it.
    let languageModel = LanguageModelManager(
      service: MLXLanguageModelService(), releaseImageModel: { await connection.releaseImageModel() },
      isImageModelBusy: { connection.isImageWorkActive() })
    // Control starts on an empty place of its own: the real state is read from the project that opens, and the state of
    // before projects stays where it is until the first project adopts it.
    let noProject = FileManager.default.temporaryDirectory.appendingPathComponent("DTHub-noproject", isDirectory: true)
    try? FileManager.default.removeItem(at: noProject)
    let control = ControlStore(
      storage: FileReferenceStorage(folder: noProject.appendingPathComponent("Control", isDirectory: true)),
      fileURL: noProject.appendingPathComponent("control.json"))
    let selection = DefaultsProjectSelection()
    let generation = GenerationController(
      languageModel: languageModel, control: control, restoringProject: selection.currentName())
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
    // Contributions land on the Generation tab; a plug-in's question goes to the language model.
    generation.attach(plugins.contributions)
    plugins.presetStore = generation.presets
    plugins.askLanguageModel = { prompt, images, options, name, history in
      try await languageModel.respond(
        to: prompt, images: images, options: options, modelNamed: name, history: history)
    }
    plugins.currentParameters = { generation.parameters }
    plugins.currentPrompts = { (generation.prompt, generation.negativePrompt) }
    plugins.startImageStrength = {
      guard control.inputs.image != nil else { return nil }
      return control.inputs.effectiveStrength(
        editModel: generation.isEditModel(in: connection),
        hasMargins: control.hasMargins(
          canvasWidth: generation.parameters.width, canvasHeight: generation.parameters.height))
    }
    plugins.startImagePath = { control.startImageURL?.path }
    plugins.moodboardPaths = { control.moodboardURLs.map(\.path) }
    plugins.languageModels = {
      languageModel.availableModels().map {
        let fields = languageModel.settings.assignments[$0.name]?.pluginFields
        return PluginLanguageModel(
          name: $0.name, path: $0.path, supportsImages: $0.supportsImages, family: fields?.family, use: fields?.use)
      }
    }
    // The project: Control, the strip of results, the parameters and the plug-ins follow the one that is open.
    let projects = ProjectManager(
      outputFolder: { OutputSettingsStore().folder() }, selection: selection, legacy: .live,
      canSwitch: { !generation.isBusyForProjectSwitch() },
      onOpen: { project, reason in
        control.switchTo(storage: FileReferenceStorage(folder: project.controlFolder), fileURL: project.controlFile)
        await generation.session.switchHistory(to: ResultsHistoryStore(fileURL: project.resultsFile))
        generation.projectFolder = project.folder
        generation.projectName = project.name
        switch reason {
        case .created(let adoptsLegacy):
          // The first project ever keeps the session of before, as it keeps Control; a later one starts from zero.
          if !adoptsLegacy { generation.apply(nil, in: connection) }
        case .reopened:
          generation.apply(ProjectImages.latestJob(in: project), in: connection)
        case .launch:
          // A session read back at launch (this project's) is more recent than the last image: it stays.
          if !generation.sessionWasRestored { generation.apply(ProjectImages.latestJob(in: project), in: connection) }
        }
        generation.saveSessionNow()
        plugins.projectChanged(project, adoptLegacy: reason == .created(adoptsLegacy: true))
      })
    plugins.currentProject = { projects.current.map { ($0, adoptLegacy: false) } }
    _projects = State(initialValue: projects)
    plugins.start(skipping: NSEvent.modifierFlags.contains(.option))
    _plugins = State(initialValue: plugins)
    // A download cut short by quitting leaves a hidden folder with part of a model: remove it.
    let leftovers = URL(fileURLWithPath: languageModel.settings.folder, isDirectory: true)
      .appendingPathComponent(RecommendedLanguageModel.folderName, isDirectory: true).deletingLastPathComponent()
    Task.detached { HubLanguageModelDownloader.removeLeftoverStaging(in: leftovers) }
  }

  var body: some Scene {
    WindowGroup(String(localized: "app.title")) {
      MainWindowView(
        workspace: workspace, connection: connection, generation: generation, plugins: plugins, projects: projects)
        .environment(canvasWindow)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
          generation.saveSessionNow()
        }
    }
    .windowResizability(.contentMinSize)
    .commands {
      CommandMenu(String(localized: "tab.generation")) {
        GenerationCommands(generation: generation, connection: connection)
      }
      CommandMenu(String(localized: "menu.tabs")) {
        TabCommands(workspace: workspace)
      }
    }

    Window(String(localized: "results.title"), id: ResultsWindow.id) {
      ResultsView(controller: generation, connection: connection)
    }
    .windowResizability(.contentMinSize)

    Window(String(localized: "lora.manager.title"), id: LoRAManagerWindow.id) {
      LoRAManagerView(connection: connection, controller: generation)
    }
    .windowResizability(.contentMinSize)

    Window(String(localized: "canvas.window.title"), id: CanvasWindow.id) {
      CanvasWindowView(generation: generation)
        .environment(canvasWindow)
    }
    .windowResizability(.contentMinSize)

    Settings {
      PreferencesView(
        connection: connection, generation: generation, languageModel: languageModel, download: download,
        plugins: plugins, projects: projects)
    }
  }
}
