import AppKit
import HubCore
import HubKit
import Observation
import SwiftUI

/// What the server step edits: both servers' settings stay local until Connect (or Next), like in Preferences.
@MainActor
@Observable
final class OnboardingServerDraft {
  var attach: ConnectionSettings
  var managed: ManagedServerSettings
  var secret: String
  var portText: String
  var managedPortText: String
  /// True once Connect was pressed (or the Draw Things server answered already): the default settings are always valid.
  var attachConfirmed: Bool
  var choice: ServerMode = .attach

  @ObservationIgnored private let connection: DrawThingsConnection
  @ObservationIgnored private var lastApplied: Applied?

  private struct Applied: Equatable {
    var attach: ConnectionSettings
    var managed: ManagedServerSettings
    var secret: String
  }

  init(connection: DrawThingsConnection) {
    self.connection = connection
    attach = connection.settings
    var managed = connection.managed
    // A program found in the usual places is offered; nothing is looked for elsewhere.
    if managed.binaryPath.isEmpty, let found = CLILocator.find() { managed.binaryPath = found }
    self.managed = managed
    secret = connection.savedSecret()
    portText = String(connection.settings.port)
    managedPortText = String(managed.port)
    attachConfirmed = connection.managed.mode == .attach && connection.monitor.status == .connected
    choice = connection.managed.mode
  }

  var plan: OnboardingServerPlan {
    OnboardingServerPlan(attach: attach, attachConfirmed: attachConfirmed, managed: managed, choice: choice)
  }

  /// Applies what the plan resolves to: the server in use now. Nothing to do while neither is set up.
  func apply() async {
    guard let mode = plan.resolvedMode else { return }
    var chosen = managed
    chosen.mode = mode
    lastApplied = Applied(attach: attach, managed: managed, secret: secret)
    await connection.apply(attach, secret: secret, managed: chosen)
  }

  /// On Next: applies only if something changed since the last Connect.
  func applyIfNeeded() async {
    guard plan.canAdvance, lastApplied != Applied(attach: attach, managed: managed, secret: secret) else { return }
    await apply()
  }

  func connect() async {
    attachConfirmed = true
    await apply()
  }
}

/// Setup step › Server: Draw Things already running, the gRPCServerCLI DT Hub starts, or both; one is enough to go on.
struct OnboardingServerStep: View {
  let connection: DrawThingsConnection
  @Bindable var draft: OnboardingServerDraft
  @State private var isApplying = false

  private static let releasesURL = URL(string: "https://github.com/drawthingsai/draw-things-community/releases")!

  var body: some View {
    Form {
      Section {
        Text("onboarding.server.intro").foregroundStyle(.secondary)
      }

      Section {
        TextField("prefs.dt.host", text: $draft.attach.host)
        TextField("prefs.dt.port", text: $draft.portText)
          .onChange(of: draft.portText) { draft.attach.port = ConnectionSettings.parsePort(draft.portText) ?? 0 }
        Toggle("prefs.dt.tls", isOn: $draft.attach.useTLS)
        SecureField("prefs.dt.secret", text: $draft.secret, prompt: Text("prefs.dt.secret.placeholder"))
        HStack(spacing: DS.controlGap) {
          DSStatusDot(status: connection.indicator)
          Text(statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(2)
          Spacer(minLength: DS.controlGap)
          Button("prefs.dt.connect") {
            Task {
              isApplying = true
              await draft.connect()
              isApplying = false
            }
          }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(draft.attach.validationError != nil || isApplying)
        }
      } header: {
        Text("onboarding.server.attach.header")
      } footer: {
        if let validationMessage {
          Text(validationMessage).foregroundStyle(DS.remove)
        }
      }

      Section {
        HStack(spacing: DS.controlGap) {
          TextField("prefs.server.binary", text: $draft.managed.binaryPath)
          Button("prefs.server.choose") { choose(directories: false) { draft.managed.binaryPath = $0 } }
        }
        // Always there: the program is a separate download from Draw Things' releases.
        Link("prefs.server.get", destination: Self.releasesURL)
        HStack(spacing: DS.controlGap) {
          TextField("prefs.server.models", text: $draft.managed.modelsFolder)
          Button("prefs.server.choose") { choose(directories: true) { draft.managed.modelsFolder = $0 } }
        }
        Button("prefs.server.models.useApp") {
          draft.managed.modelsFolder = CLILocator.drawThingsAppModelsFolder()
        }
        TextField("prefs.server.port", text: $draft.managedPortText)
          .onChange(of: draft.managedPortText) {
            draft.managed.port = ConnectionSettings.parsePort(draft.managedPortText) ?? 0
          }
      } header: {
        Text("onboarding.server.managed.header")
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          if draft.managed.binaryPath.isEmpty == false || draft.managed.modelsFolder.isEmpty == false,
            let problem = draft.managed.validationError()
          {
            Text(ManagedServerText.headline(problem)).foregroundStyle(DS.remove)
          } else if draft.managed.warning() == .modelsFolderDenied {
            Text("prefs.folder.denied").foregroundStyle(DS.remove)
            PrivacySettingsLink()
          }
          Text("prefs.server.note").foregroundStyle(.secondary)
        }
      }

      if draft.plan.needsChoice {
        Section {
          Picker("onboarding.server.choice", selection: $draft.choice) {
            Text("onboarding.server.choice.attach").tag(ServerMode.attach)
            Text("onboarding.server.choice.managed").tag(ServerMode.managed)
          }
          .pickerStyle(.segmented)
        }
      }

      if !draft.plan.canAdvance {
        Section {
          Text("onboarding.server.needOne").foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
  }

  private func choose(directories: Bool, _ pick: (String) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = !directories
    panel.canChooseDirectories = directories
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url { pick(url.path) }
  }

  private var validationMessage: String? {
    switch draft.attach.validationError {
    case .emptyHost: String(localized: "prefs.dt.error.emptyHost")
    case .invalidHost: String(localized: "prefs.dt.error.invalidHost")
    case .invalidPort: String(localized: "prefs.dt.error.invalidPort")
    case nil: nil
    }
  }

  /// The same sentence the Draw Things tab of Preferences shows.
  private var statusLine: String {
    let monitor = connection.monitor
    if connection.managed.mode == .managed, monitor.status != .connected, connection.indicator == .connecting {
      return String(localized: "status.serverStarting")
    }
    if connection.managed.mode == .managed, let problem = ManagedServerText.problem(connection.managedServer.state) {
      return problem
    }
    guard monitor.status == .connected else {
      return ConnectionStatusText.headline(status: monitor.status, error: monitor.lastError)
    }
    if monitor.catalog.isModelBrowsingDisabled { return connection.noModelsText }
    return String(format: String(localized: "prefs.dt.models"), monitor.catalog.models.count)
  }
}
