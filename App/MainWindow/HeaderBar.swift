import AppKit
import HubCore
import HubKit
import SwiftUI

/// [Project ▾] [Model ▾ · family] [DT+] [CU] … ● [⚙︎] [▶ Run] (spec §7); the plug-in menu is in the tab bar and the Results button beside the header.
struct HeaderBar: View {
  let connection: DrawThingsConnection
  let generation: GenerationController
  let plugins: PluginRegistry
  let projects: ProjectManager
  @State private var showNewProject = false
  /// DT+ model picker: open or not, and what is open inside (kept while the app runs).
  @State private var showModelPicker = false
  @State private var modelTree = ModelTreeState()
  @Environment(\.openWindow) private var openWindow

  private var monitor: ConnectionMonitor { connection.monitor }
  private var selection: ModelSelection { connection.selection }
  private var selectedModel: CatalogModel? { selection.selectedModel(in: monitor.catalog) }

  private var runBlocker: RunBlocker? { connection.runBlocker }

  var body: some View {
    HStack(spacing: DS.controlGap) {
      projectMenu
      modelMenu
      dtPlusButton
      if connection.dtPlus && connection.canUseDTPlus {
        CUMeterView(connection: connection, generation: generation)
      }
      Spacer(minLength: DS.groupGap)
      DSStatusDot(status: connection.indicator)
        .padding(.horizontal, 6)
        .help(statusText)
        .accessibilityLabel(statusText)
      SettingsLink {
        Image(systemName: "gearshape")
      }
      .buttonStyle(DSGlassCircleButtonStyle())
      .help(String(localized: "header.preferences"))
      .accessibilityLabel(String(localized: "header.preferences"))
      incrementalButton
      runButton
    }
    .padding(.horizontal, DS.panelPadding)
    .padding(.vertical, 10)
    .dsPanel()
  }

  /// DT+: with the Draw Things app's server in Bridge Mode, the models of Draw Things' lists that are not downloaded
  /// are offered too, and run in the cloud. Teal while on; off and disabled with the server DT Hub starts.
  private var dtPlusButton: some View {
    let on = connection.dtPlus && connection.canUseDTPlus
    return Button {
      Task { await connection.setDTPlus(!connection.dtPlus) }
    } label: {
      Text(verbatim: "DT+")
        .fontWeight(.semibold)
        .foregroundStyle(on ? DS.accent : Color.primary)
    }
    .buttonStyle(DSPillButtonStyle())
    .disabled(!connection.canUseDTPlus || generation.session.isRunning || generation.isPreparing)
    .help(String(localized: connection.canUseDTPlus ? "header.dtplus.help" : "header.dtplus.managed"))
    .accessibilityLabel(String(localized: "header.dtplus.help"))
    .accessibilityValue(String(localized: on ? "header.incremental.on" : "header.incremental.off"))
  }

  /// Incremental mode: each result becomes the start image of the next RUN. Teal and filled while on.
  private var incrementalButton: some View {
    Button {
      generation.incremental.toggle()
    } label: {
      Image(systemName: generation.incremental ? "arrowshape.bounce.right.fill" : "arrowshape.bounce.right")
        .foregroundStyle(generation.incremental ? DS.accent : Color.primary)
    }
    .buttonStyle(DSGlassCircleButtonStyle())
    .help(String(localized: "header.incremental.help"))
    .accessibilityLabel(String(localized: "header.incremental.help"))
    .accessibilityValue(String(localized: generation.incremental ? "header.incremental.on" : "header.incremental.off"))
  }

  /// The open project's name; its menu lists the projects (the open one checked), makes a new one and shows the
  /// project in the Finder. The projects cannot change during a RUN.
  private var projectMenu: some View {
    let busy = generation.isBusyForProjectSwitch()
    return Menu {
      ForEach(projects.projects) { project in
        Toggle(
          isOn: Binding(
            get: { projects.current?.name == project.name },
            set: { _ in Task { await projects.open(project) } })
        ) {
          Text(verbatim: project.name)
        }
        .disabled(busy)
      }
      if !projects.projects.isEmpty { Divider() }
      Button("project.new") { showNewProject = true }
        .disabled(busy)
      Button("project.reveal") {
        if let folder = projects.current?.folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
      }
      .disabled(projects.current == nil)
    } label: {
      DSMenuLabel(projects.current?.name ?? "—", systemImage: "folder")
    }
    .dsMenuPill()
    .help(String(localized: "project.menu"))
    .onAppear { projects.refresh() }
    .sheet(isPresented: $showNewProject) { NewProjectSheet(projects: projects) }
  }

  /// With DT+ on, the models are many: a panel with a search field and the lists as groups that open and close. With DT+
  /// off, the menu of the models installed on the server, as always.
  @ViewBuilder private var modelMenu: some View {
    if connection.dtPlus && connection.canUseDTPlus {
      modelPickerButton
    } else {
      Menu {
        modelMenuContent
      } label: {
        DSMenuLabel(modelTitle, detail: modelDetail, systemImage: "cube")
      }
      .dsMenuPill()
    }
  }

  private var modelPickerButton: some View {
    Button {
      showModelPicker.toggle()
    } label: {
      DSMenuLabel(modelTitle, detail: modelDetail, systemImage: "cube")
    }
    .buttonStyle(.plain)
    .font(.system(size: 13, weight: .semibold))
    .padding(.horizontal, DS.pillHPadding)
    .frame(maxWidth: 320)
    .frame(height: DS.pillHeight)
    .dsGlass(Capsule(style: .continuous))
    .fixedSize()
    .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
      ModelPickerView(
        catalog: monitor.catalog, selectedFile: selection.selectedFile, message: modelPickerMessage, state: $modelTree
      ) { model in
        generation.chooseModel(model.file, in: connection)
      }
    }
  }

  /// Why the picker has nothing to show, as the menu says it; nil when there are models.
  private var modelPickerMessage: String? {
    if monitor.status != .connected { return String(localized: "header.model.unavailable") }
    if monitor.catalog.isModelBrowsingDisabled { return connection.noModelsText }
    return nil
  }

  /// Models grouped by family, the selected one checked (spec §5, §7).
  @ViewBuilder private var modelMenuContent: some View {
    if monitor.status != .connected {
      Text("header.model.unavailable")
    } else if monitor.catalog.isModelBrowsingDisabled {
      Text(verbatim: connection.noModelsText)
    } else if monitor.catalog.models.isEmpty {
      Text("header.model.empty")
    } else {
      ForEach(monitor.catalog.modelsByFamily) { group in
        Section {
          ForEach(group.models) { model in
            Toggle(
              isOn: Binding(
                get: { selection.selectedFile == model.file },
                set: { _ in generation.chooseModel(model.file, in: connection) })
            ) {
              // A model that is not downloaded runs in the cloud (DT+).
              if model.isRemote {
                Label(model.name, systemImage: "cloud")
              } else {
                Text(verbatim: model.name)
              }
            }
          }
        } header: {
          Text(verbatim: group.family ?? "—")
        }
      }
    }
  }

  private var modelTitle: String {
    if let selectedModel { return selectedModel.name }
    return selection.selectedFile ?? String(localized: "header.model.none")
  }

  /// The family of the selected model, or a warning when the server lacks it.
  private var modelDetail: String? {
    if let selectedModel { return selectedModel.family }
    if selection.selectedFile != nil, monitor.status == .connected,
      !monitor.catalog.isModelBrowsingDisabled
    {
      return String(localized: "header.model.missing")
    }
    return nil
  }

  /// The step shown beside Stop; nil while the memory is being prepared.
  private var runningProgress: (step: Int?, total: Int)? {
    if case .running(let step, let total) = generation.session.phase { return (step, total) }
    return nil
  }

  /// RUN, or Stop with the progress while a generation runs (spec §7). ⌘↩ and ⌘. are in the
  /// Generation menu (`GenerationCommands`), so they work from every window.
  @ViewBuilder private var runButton: some View {
    if generation.session.isRunning || generation.isPreparing {
      let progress = runningProgress
      Button {
        generation.stop()
      } label: {
        HStack(spacing: DS.pillIconGap) {
          Image(systemName: "stop.fill")
            .font(.system(size: 14, weight: .semibold))
            .accessibilityHidden(true)
          Text("header.stop")
          if let pass = generation.pipelinePass {
            Text(verbatim: String(format: String(localized: "header.stop.pass"), pass.index, pass.count))
          }
          if let step = progress?.step, let total = progress?.total {
            Text(verbatim: "\(step)/\(total)")
              .monospacedDigit()
          }
        }
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
      .help(String(localized: "header.stop.help"))
    } else {
      let pipeline = plugins.contributions.pipeline
      Button {
        if generation.run(with: connection) { openWindow(id: ResultsWindow.id) }
      } label: {
        HStack(spacing: DS.pillIconGap) {
          Image(systemName: "play.fill")
            .font(.system(size: 14, weight: .semibold))
            .accessibilityHidden(true)
          if let pipeline {
            Text(verbatim: ContributionText.runTitle(passes: pipeline.pipeline.steps.count))
          } else {
            Text("header.run")
          }
        }
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
      .disabled(runBlocker != nil || generation.isPreparing || projects.current == nil)
      .help(runBlocker == nil ? (pipeline.map { ContributionText.pipelineHelp($0, plugins: plugins) } ?? runHelp) : runHelp)
      .contextMenu {
        if pipeline != nil {
          Button("header.run.removePipeline") { plugins.contributions.removePipeline() }
        }
      }
    }
  }

  private var runHelp: String {
    switch runBlocker {
    case .notConnected: String(localized: "run.blocked.notConnected")
    case .noModelSelected: String(localized: "run.blocked.noModel")
    case .modelBrowsingDisabled: connection.noModelsText
    case .modelNotOnServer: String(localized: "run.blocked.modelMissing")
    case nil: String(localized: "header.run.help")
    }
  }

  private var statusText: String {
    if connection.releasedForLanguageModel { return String(localized: "status.imageModelParked") }
    if connection.managed.mode == .managed, connection.managedServer.isStarting, monitor.status != .connected {
      return String(localized: "status.serverStarting")
    }
    if monitor.status == .connected, monitor.catalog.isModelBrowsingDisabled {
      return connection.noModelsText
    }
    return ConnectionStatusText.headline(status: monitor.status, error: monitor.lastError)
  }
}
