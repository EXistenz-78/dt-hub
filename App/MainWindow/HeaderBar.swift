import HubCore
import HubKit
import SwiftUI

/// [Plug-ins ▾] [Model ▾] … ● DT [⚙︎] [▶ Run] (spec §7).
struct HeaderBar: View {
  let connection: ConnectionStatus
  let selectedModel: String?

  private var runBlocker: RunBlocker? {
    RunAvailability.blocker(connection: connection, selectedModel: selectedModel)
  }

  var body: some View {
    HStack(spacing: DS.controlGap) {
      pluginsMenu
      modelMenu
      Spacer(minLength: DS.groupGap)
      DSStatusDot(status: connection)
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
      Text("header.model.unavailable")
    } label: {
      DSMenuLabel(selectedModel ?? String(localized: "header.model.none"), systemImage: "cube")
    }
    .dsMenuPill()
  }

  private var runButton: some View {
    Button {
      // Generation arrives in M3; until then RUN is always blocked (no connection).
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
    case nil: String(localized: "header.run.help")
    }
  }

  private var statusText: String {
    switch connection {
    case .connected: String(localized: "status.connected")
    case .connecting: String(localized: "status.connecting")
    case .disconnected: String(localized: "status.disconnected")
    }
  }
}
