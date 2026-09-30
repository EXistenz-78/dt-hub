import HubCore
import HubKit
import SwiftUI

/// [Plug-ins ▾] [Model ▾ · family] … ● DT [⚙︎] [▶ Run] (spec §7).
struct HeaderBar: View {
  let connection: DrawThingsConnection

  private var monitor: ConnectionMonitor { connection.monitor }
  private var selection: ModelSelection { connection.selection }
  private var selectedModel: CatalogModel? { selection.selectedModel(in: monitor.catalog) }

  private var runBlocker: RunBlocker? {
    RunAvailability.blocker(
      connection: monitor.status, selectedModel: selection.selectedFile, catalog: monitor.catalog)
  }

  var body: some View {
    HStack(spacing: DS.controlGap) {
      pluginsMenu
      modelMenu
      Spacer(minLength: DS.groupGap)
      DSStatusDot(status: monitor.indicator)
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
      Text("header.plugins.none")
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
      Text("header.model.browsingDisabled")
    } else if monitor.catalog.models.isEmpty {
      Text("header.model.empty")
    } else {
      ForEach(monitor.catalog.modelsByFamily) { group in
        Section {
          ForEach(group.models) { model in
            Toggle(
              isOn: Binding(
                get: { selection.selectedFile == model.file },
                set: { _ in selection.select(model.file) })
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

  private var runButton: some View {
    Button {
      // Generation arrives in M3.
    } label: {
      HStack(spacing: DS.pillIconGap) {
        Image(systemName: "play.fill")
          .font(.system(size: 14, weight: .semibold))
        Text("header.run")
      }
    }
    .buttonStyle(DSPillButtonStyle(prominent: true))
    .disabled(runBlocker != nil)
    .keyboardShortcut(.return, modifiers: .command)
    .help(runHelp)
  }

  private var runHelp: String {
    switch runBlocker {
    case .notConnected: String(localized: "run.blocked.notConnected")
    case .noModelSelected: String(localized: "run.blocked.noModel")
    case .modelBrowsingDisabled: String(localized: "header.model.browsingDisabled")
    case .modelNotOnServer: String(localized: "run.blocked.modelMissing")
    case nil: String(localized: "header.run.help")
    }
  }

  private var statusText: String {
    if monitor.status == .connected, monitor.catalog.isModelBrowsingDisabled {
      return String(localized: "header.model.browsingDisabled")
    }
    return ConnectionStatusText.headline(status: monitor.status, error: monitor.lastError)
  }
}
