import AppKit
import HubCore
import HubKit
import SwiftUI

/// Preferences › Draw Things: how DT Hub reaches the server — one already running, or a
/// gRPCServerCLI that DT Hub starts — and whether it is reached (spec §5, §7). Edits stay
/// local until Connect, so typing does not reconnect on every keystroke.
struct DrawThingsPreferencesView: View {
  let connection: DrawThingsConnection

  @State private var draft = ConnectionSettings.default
  @State private var managedDraft = ManagedServerSettings.default
  @State private var secret = ""
  /// The ports as typed: parsed on every keystroke, so Connect never uses a stale value.
  @State private var portText = ""
  @State private var managedPortText = ""
  @State private var isApplying = false

  private var monitor: ConnectionMonitor { connection.monitor }
  private var server: ManagedServer { connection.managedServer }
  private var isManaged: Bool { managedDraft.mode == .managed }

  /// Where Draw Things publishes the releases that include gRPCServerCLI.
  private static let releasesURL = URL(string: "https://github.com/drawthingsai/draw-things-community/releases")!

  var body: some View {
    Form {
      Section {
        Picker("prefs.server.mode", selection: $managedDraft.mode) {
          Text("prefs.server.mode.attach").tag(ServerMode.attach)
          Text("prefs.server.mode.managed").tag(ServerMode.managed)
        }
        .pickerStyle(.segmented)
      }

      if isManaged {
        managedSection
      } else {
        attachSection
      }

      Section {
        HStack(spacing: DS.controlGap) {
          DSStatusDot(status: connection.indicator)
          VStack(alignment: .leading, spacing: 2) {
            Text(statusLine)
            if case .unreachable(let detail)? = monitor.lastError, connection.indicator != .connecting {
              Text(verbatim: detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
          Spacer(minLength: DS.controlGap)
          Button("prefs.dt.connect") {
            Task {
              isApplying = true
              await connection.apply(draft, secret: secret, managed: managedDraft)
              isApplying = false
            }
          }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
          .disabled(!canApply || isApplying)
        }
        if connection.secretSaveFailed {
          Text("prefs.dt.secret.saveError")
            .foregroundStyle(DS.remove)
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      draft = connection.settings
      managedDraft = connection.managed
      portText = String(connection.settings.port)
      managedPortText = String(connection.managed.port)
      secret = connection.savedSecret()
      // A program found in the usual places is offered; nothing is looked for elsewhere.
      if managedDraft.binaryPath.isEmpty, let found = CLILocator.find() { managedDraft.binaryPath = found }
    }
  }

  // MARK: Attach to a running server

  private var attachSection: some View {
    Section {
      TextField("prefs.dt.host", text: $draft.host)
      TextField("prefs.dt.port", text: $portText)
        .onChange(of: portText) {
          draft.port = ConnectionSettings.parsePort(portText) ?? 0
        }
      Toggle("prefs.dt.tls", isOn: $draft.useTLS)
      SecureField("prefs.dt.secret", text: $secret, prompt: Text("prefs.dt.secret.placeholder"))
    } footer: {
      if let validationMessage {
        Text(validationMessage)
          .foregroundStyle(DS.remove)
      } else {
        Text("prefs.dt.note")
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: DT Hub starts the server

  @ViewBuilder private var managedSection: some View {
    Section {
      HStack(spacing: DS.controlGap) {
        TextField("prefs.server.binary", text: $managedDraft.binaryPath)
        Button("prefs.server.choose") { choose(directories: false) { managedDraft.binaryPath = $0 } }
      }
      HStack(spacing: DS.controlGap) {
        TextField("prefs.server.models", text: $managedDraft.modelsFolder)
        Button("prefs.server.choose") { choose(directories: true) { managedDraft.modelsFolder = $0 } }
      }
      Button("prefs.server.models.useApp") {
        managedDraft.modelsFolder = CLILocator.drawThingsAppModelsFolder()
      }
      TextField("prefs.server.port", text: $managedPortText)
        .onChange(of: managedPortText) {
          managedDraft.port = ConnectionSettings.parsePort(managedPortText) ?? 0
        }
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        if let problem = managedDraft.validationError() {
          Text(ManagedServerText.headline(problem))
            .foregroundStyle(DS.remove)
        } else if managedDraft.warning() == .noModelFiles {
          Text("prefs.server.noModelFiles")
            .foregroundStyle(DS.remove)
        }
        Text("prefs.server.note")
          .foregroundStyle(.secondary)
        if managedDraft.binaryPath.isEmpty || managedDraft.validationError() == .binaryNotExecutable {
          Link("prefs.server.get", destination: Self.releasesURL)
        }
      }
    }

    versionSection

    if !server.logTail.isEmpty || server.isRunning {
      Section {
        if server.isRunning {
          Button("prefs.server.stop") { server.stop() }
        }
        if !server.logTail.isEmpty {
          DisclosureGroup("prefs.server.log") {
            Text(verbatim: server.logTail.joined(separator: "\n"))
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
  }

  // MARK: Version of the server

  /// The version of the gRPCServerCLI, recognized by its sha256 among the Draw Things releases, and whether a newer
  /// one is out: checked at launch and here on demand.
  private var versionSection: some View {
    let info = connection.serverVersion
    return Section {
      HStack(spacing: DS.controlGap) {
        VStack(alignment: .leading, spacing: 2) {
          Text("prefs.server.version")
          Text(verbatim: versionLine(info))
            .font(.caption)
            .foregroundStyle(info.state == .updateAvailable ? DS.accent : .secondary)
        }
        Spacer(minLength: DS.controlGap)
        if info.state == .updateAvailable || info.state == .unidentified {
          Link("prefs.server.version.download", destination: Self.releasesURL)
        }
        Button("prefs.server.version.check") { Task { await connection.refreshServerVersion() } }
          .buttonStyle(DSPillButtonStyle())
          .disabled(info.state == .checking)
      }
    } footer: {
      Text("prefs.server.version.note")
        .foregroundStyle(.secondary)
    }
  }

  private func versionLine(_ info: ServerVersionInfo) -> String {
    switch info.state {
    case .idle, .noProgram: return "—"
    case .checking: return String(localized: "prefs.server.version.checking")
    case .upToDate: return String(format: String(localized: "prefs.server.version.upToDate"), info.installed ?? "")
    case .updateAvailable:
      return String(
        format: String(localized: "prefs.server.version.update"), info.installed ?? "", info.latest ?? "")
    case .unidentified:
      return String(format: String(localized: "prefs.server.version.unknown"), info.latest ?? "")
    case .couldNotCheck:
      return info.installed.map { String(format: String(localized: "prefs.server.version.offline"), $0) }
        ?? String(localized: "prefs.server.version.offlineUnknown")
    }
  }

  private func choose(directories: Bool, _ pick: (String) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = !directories
    panel.canChooseDirectories = directories
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url { pick(url.path) }
  }

  // MARK: Status

  private var canApply: Bool {
    isManaged ? managedDraft.validationError() == nil : draft.validationError == nil
  }

  private var validationMessage: String? {
    switch draft.validationError {
    case .emptyHost: String(localized: "prefs.dt.error.emptyHost")
    case .invalidHost: String(localized: "prefs.dt.error.invalidHost")
    case .invalidPort: String(localized: "prefs.dt.error.invalidPort")
    case nil: nil
    }
  }

  private var statusLine: String {
    if connection.managed.mode == .managed, monitor.status != .connected, connection.indicator == .connecting {
      return String(localized: "status.serverStarting")
    }
    if connection.managed.mode == .managed, let problem = ManagedServerText.problem(server.state) {
      return problem
    }
    guard monitor.status == .connected else {
      return ConnectionStatusText.headline(status: monitor.status, error: monitor.lastError)
    }
    if monitor.catalog.isModelBrowsingDisabled {
      return connection.noModelsText
    }
    return String(format: String(localized: "prefs.dt.models"), monitor.catalog.models.count)
  }
}
