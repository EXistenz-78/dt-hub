import HubCore
import HubKit
import SwiftUI

/// [Plug-ins ▾] [Model ▾ · family] … ● DT [⚙︎] [▶ Run] (spec §7).
struct HeaderBar: View {
  let connection: DrawThingsConnection
  let generation: GenerationController
  let plugins: PluginRegistry
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings

  private var monitor: ConnectionMonitor { connection.monitor }
  private var selection: ModelSelection { connection.selection }
  private var selectedModel: CatalogModel? { selection.selectedModel(in: monitor.catalog) }

  private var runBlocker: RunBlocker? { connection.runBlocker }

  var body: some View {
    HStack(spacing: DS.controlGap) {
      pluginsMenu
      modelMenu
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
      runButton
    }
    .padding(.horizontal, DS.panelPadding)
    .padding(.vertical, 10)
    .dsPanel()
  }

  private var pluginsMenu: some View {
    Menu {
      let loaded = plugins.entries.filter { $0.state == .loaded }
      if loaded.isEmpty {
        Text("header.plugins.none")
      }
      ForEach(loaded) { entry in
        Toggle(
          entry.name,
          isOn: Binding(get: { entry.isActive }, set: { plugins.setActive(entry.id, $0) })
        )
        .disabled(!plugins.isCompatible(entry))
        .help(plugins.isCompatible(entry) ? "" : String(localized: "header.plugins.incompatible"))
      }
      Divider()
      Button("header.plugins.manage") { openSettings() }
    } label: {
      DSMenuLabel(String(localized: "header.plugins"), systemImage: "puzzlepiece.extension")
    }
    .dsMenuPill()
  }

  private var modelMenu: some View {
    Menu {
      modelMenuContent
    } label: {
      DSMenuLabel(modelTitle, detail: modelDetail, systemImage: "cube")
    }
    .dsMenuPill()
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
              Text(verbatim: model.name)
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
      .disabled(runBlocker != nil || generation.isPreparing)
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
