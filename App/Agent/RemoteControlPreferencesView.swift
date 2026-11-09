import AppKit
import DTHubDesign
import HubMCP
import SwiftUI

/// Preferences › Remote control (spec 2026-11-08 §6): the switch, what an agent may do, the budget, the token and the log.
struct RemoteControlPreferencesView: View {
  @Environment(RemoteControlModel.self) private var remote

  var body: some View {
    @Bindable var remote = remote
    Form {
      Section {
        Toggle(String(localized: "remote.enable"), isOn: $remote.settings.enabled)
        Text(String(localized: "remote.warning")).font(.caption).foregroundStyle(.secondary)
        if let port = remote.listeningPort, remote.isRunning {
          Text(String(format: String(localized: "remote.status.running"), Int(port))).foregroundStyle(.secondary)
        } else if let error = remote.lastError {
          Text(error).foregroundStyle(.red)
        } else {
          Text(String(localized: "remote.status.off")).foregroundStyle(.secondary)
        }
      }
      Section {
        LabeledContent(String(localized: "remote.port")) {
          TextField(String(localized: "remote.port"), value: $remote.settings.port, format: .number.grouping(.never)).frame(width: 90)
            .multilineTextAlignment(.trailing)
        }
        Picker(String(localized: "remote.mode"), selection: $remote.settings.mode) {
          Text(String(localized: "remote.mode.readOnly")).tag(AccessMode.readOnly)
          Text(String(localized: "remote.mode.editFields")).tag(AccessMode.editFields)
          Text(String(localized: "remote.mode.full")).tag(AccessMode.full)
        }
        Stepper(value: $remote.settings.confirmThreshold, in: 1...1000) {
          Text(verbatim: "\(String(localized: "remote.threshold")): \(remote.settings.confirmThreshold)")
        }
        Stepper(value: $remote.settings.imageBudget, in: 1...100_000, step: 10) {
          Text(verbatim: "\(String(localized: "remote.budget.images")): \(remote.settings.imageBudget)")
        }
        Stepper(value: cuBinding, in: 0...1_000_000, step: 100) {
          Text(verbatim: "\(String(localized: "remote.budget.cu")): \(remote.settings.cuBudget ?? 0)")
        }
        Stepper(value: $remote.settings.confirmTimeoutSeconds, in: 5...600, step: 5) {
          Text(verbatim: "\(String(localized: "remote.timeout")): \(remote.settings.confirmTimeoutSeconds)")
        }
      }
      Section(String(localized: "remote.folders")) {
        ForEach(remote.settings.allowedFolders, id: \.self) { folder in
          HStack {
            Text(folder).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(String(localized: "remote.folders.remove")) {
              remote.settings.allowedFolders.removeAll { $0 == folder }
            }
          }
        }
        Button(String(localized: "remote.folders.add")) { addFolder() }
      }
      Section {
        Text(
          String(
            format: String(localized: "remote.session.used"), remote.ledger.usedImages, remote.settings.imageBudget))
        if remote.ledger.isConfirmed {
          Text(String(localized: "remote.session.authorised")).foregroundStyle(.secondary)
        }
        HStack {
          Button(String(localized: "remote.session.authorise")) { remote.authorizeSession() }
            .disabled(remote.ledger.isConfirmed)
          Button(String(localized: "remote.session.reset")) { remote.resetSession() }
        }
        if remote.connectedClients > 0 {
          Text(String(format: String(localized: "remote.clients"), remote.connectedClients)).foregroundStyle(.secondary)
          Button(String(localized: "remote.stop"), role: .destructive) { remote.killSwitch() }
        }
      }
      Section(String(localized: "remote.token")) {
        HStack {
          Button(String(localized: "remote.token.copy")) { remote.copyToPasteboard(remote.token) }
          Button(String(localized: "remote.token.regenerate")) { remote.regenerateToken() }
        }
        Button(String(localized: "remote.config.copy")) { remote.copyToPasteboard(remote.clientConfiguration) }
        Button(String(localized: "remote.instructions.copy")) { remote.copyToPasteboard(AgentInstructions.skillMarkdown()) }
      }
      Section(String(localized: "remote.log")) {
        if remote.callLog.entries.isEmpty {
          Text(String(localized: "remote.log.empty")).foregroundStyle(.secondary)
        } else {
          ForEach(remote.callLog.entries.suffix(30).reversed()) { entry in
            HStack(alignment: .firstTextBaseline) {
              Text(entry.date, format: .dateTime.hour().minute().second()).monospacedDigit().foregroundStyle(.secondary)
              Text(entry.tool).fontWeight(.medium)
              Text(entry.detail).lineLimit(1).foregroundStyle(entry.isError ? Color.red : Color.secondary)
            }
            .font(.caption)
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private var cuBinding: Binding<Int> {
    Binding(
      get: { remote.settings.cuBudget ?? 0 },
      set: { remote.settings.cuBudget = $0 == 0 ? nil : $0 })
  }

  private func addFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url, !remote.settings.allowedFolders.contains(url.path) {
      remote.settings.allowedFolders.append(url.path)
    }
  }
}

/// A small mark in the header while an agent is connected; a click stops it.
struct RemoteControlIndicator: View {
  @Environment(RemoteControlModel.self) private var remote

  var body: some View {
    if remote.connectedClients > 0 {
      Button {
        remote.killSwitch()
      } label: {
        Image(systemName: "antenna.radiowaves.left.and.right")
      }
      .buttonStyle(DSGlassCircleButtonStyle())
      .help(String(localized: "remote.indicator.help"))
      .accessibilityLabel(String(localized: "remote.indicator.help"))
    }
  }
}
