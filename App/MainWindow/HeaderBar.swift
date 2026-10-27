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
  @AppStorage(QueueSidebar.visibleKey) private var queueVisible = true
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
      Button {
        queueVisible.toggle()
      } label: {
        Image(systemName: "sidebar.left")
      }
      .buttonStyle(DSGlassCircleButtonStyle())
      .help(String(localized: "queue.toggle"))
      .accessibilityLabel(String(localized: "queue.toggle"))
      projectMenu
      modelMenu
      dtPlusPill
      Spacer(minLength: DS.groupGap)
      serverDotButton
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

  /// The status dot: a click switches between the server DT Hub starts and the one already running (settings from
  /// Preferences). Disabled while something runs, or when the other server's settings are not valid.
  private var serverDotButton: some View {
    let busy = generation.session.isRunning || generation.isPreparing
    let target = String(localized: connection.otherServerMode == .managed ? "header.server.managed" : "header.server.attach")
    let hint = connection.canSwitchServer
      ? String(format: String(localized: "header.server.switch"), target)
      : String(format: String(localized: "header.server.cannotSwitch"), target)
    return Button {
      Task { await connection.switchServer() }
    } label: {
      DSStatusDot(status: connection.indicator)
        .padding(6)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(busy || !connection.canSwitchServer)
    .help(statusText + "\n" + hint)
    .accessibilityLabel(statusText)
    .accessibilityHint(hint)
  }

  /// DT+: with the Draw Things app's server in Bridge Mode, the models of Draw Things' lists that are not downloaded
  /// are offered too, and run in the cloud. Teal while on; off and disabled with the server DT Hub starts.
  private var dtPlusPill: some View {
    let on = connection.dtPlus && connection.canUseDTPlus
    let locked = !connection.canUseDTPlus || generation.session.isRunning || generation.isPreparing
    return HStack(spacing: 10) {
      Button {
        Task { await connection.setDTPlus(!connection.dtPlus) }
      } label: {
        Text(verbatim: "DT+")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(on ? DS.accent : Color.primary)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(locked)
      .help(String(localized: connection.canUseDTPlus ? "header.dtplus.help" : "header.dtplus.managed"))
      .accessibilityLabel(String(localized: "header.dtplus.help"))
      .accessibilityValue(String(localized: on ? "header.incremental.on" : "header.incremental.off"))
      if on {
        Divider().frame(height: 18)
        CUMeterView(connection: connection, generation: generation)
      }
    }
    .padding(.horizontal, DS.pillHPadding)
    .frame(height: DS.pillHeight)
    // Never squeezed: the other items give way before DT+ does.
    .fixedSize(horizontal: true, vertical: false)
    .layoutPriority(2)
    .dsGlass(Capsule(style: .continuous))
    .opacity(connection.canUseDTPlus ? 1 : 0.4)
    .animation(.easeOut(duration: 0.15), value: on)
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
      .help(selectedModel?.family ?? "")
    }
  }

  private var modelPickerButton: some View {
    Button {
      showModelPicker.toggle()
    } label: {
      // A long model name or family is cut with "…" past 320 pt, so Run is not pushed out of a narrow window.
      CappedWidth(maxWidth: 320) { DSMenuLabel(modelTitle, detail: modelDetail, systemImage: "cube") }
    }
    .buttonStyle(.plain)
    .font(.system(size: 13, weight: .semibold))
    .padding(.horizontal, DS.pillHPadding)
    .frame(height: DS.pillHeight)
    .dsGlass(Capsule(style: .continuous))
    .fixedSize()
    .help(selectedModel?.family ?? "")
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

  /// A warning when the server lacks the selected model; the family is no longer in the pill (it is in the tooltip).
  private var modelDetail: String? {
    if selectedModel != nil { return nil }
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
        runLabel(
          title: "header.stop", icon: "stop.fill",
          pass: generation.pipelinePass.map { "\($0.index)/\($0.count)" },
          step: progress?.step.map { "\($0)/\(progress?.total ?? 0)" })
      }
      .accessibilityLabel(stopAccessibilityLabel(progress: progress))
      .buttonStyle(DSPillButtonStyle(prominent: true))
      .fixedSize()
      .help(String(localized: "header.stop.help"))
    } else {
      let pipeline = plugins.contributions.pipeline
      Button {
        if generation.run(with: connection) { openWindow(id: ResultsWindow.id) }
      } label: {
        // The same lines as Stop: the passes of the pipeline and, without one, the steps of the card.
        runLabel(
          title: "header.run", icon: "play.fill",
          pass: pipeline.map { "\($0.pipeline.passCount)" },
          step: pipeline == nil ? "\(generation.parameters.steps)" : nil)
      }
      .accessibilityLabel(
        pipeline.map { ContributionText.runTitle(passes: $0.pipeline.passCount) }
          ?? String(localized: "header.run"))
      .buttonStyle(DSPillButtonStyle(prominent: true))
      .fixedSize()
      .disabled(runBlocker != nil || generation.isPreparing || projects.current == nil)
      .help(runBlocker == nil ? (pipeline.map { ContributionText.pipelineHelp($0, plugins: plugins) } ?? runHelp) : runHelp)
      .contextMenu {
        if pipeline != nil {
          Button("header.run.removePipeline") { plugins.contributions.removePipeline() }
        }
      }
    }
  }

  /// The content of Run and of Stop: the title with its icon and, smaller below it, the pass of a pipeline and the step,
  /// each with its icon. Same layout in every state of the button.
  private func runLabel(title: LocalizedStringKey, icon: String, pass: String?, step: String?) -> some View {
    VStack(spacing: 1) {
      HStack(spacing: DS.pillIconGap) {
        Image(systemName: icon)
          .font(.system(size: 14, weight: .semibold))
          .accessibilityHidden(true)
        Text(title)
      }
      if pass != nil || step != nil {
        HStack(spacing: 8) {
          if let pass {
            Label {
              Text(verbatim: pass).monospacedDigit()
            } icon: {
              Image(systemName: "square.grid.3x3")
            }
          }
          if let step {
            Label {
              Text(verbatim: step).monospacedDigit()
            } icon: {
              Image(systemName: "shoeprints.fill")
            }
          }
        }
        .labelStyle(CompactProgressLabelStyle())
        .font(.system(size: 10, weight: .medium))
        .opacity(0.8)
      }
    }
  }

  private func stopAccessibilityLabel(progress: (step: Int?, total: Int)?) -> String {
    var parts = [String(localized: "header.stop")]
    if let pass = generation.pipelinePass {
      parts.append(String(format: String(localized: "header.stop.pass"), pass.index, pass.count))
    }
    if let step = progress?.step, let total = progress?.total {
      parts.append(String(format: String(localized: "header.stop.step"), step, total))
    }
    return parts.joined(separator: ", ")
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

/// The small progress line under Stop: the icon, a short gap, the number.
private struct CompactProgressLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 3) {
      configuration.icon
      configuration.title
    }
  }
}
