import HubCore
import HubKit
import SwiftUI

/// Preferences › Draw Things: where the server is, and whether DT Hub reaches it (spec §5, §7).
/// Edits stay local until Connect, so typing does not reconnect on every keystroke.
struct DrawThingsPreferencesView: View {
  let connection: DrawThingsConnection

  @State private var draft = ConnectionSettings.default
  @State private var secret = ""
  /// The port as typed: parsed on every keystroke, so Connect never uses a stale value.
  @State private var portText = ""
  @State private var isApplying = false

  private var monitor: ConnectionMonitor { connection.monitor }

  var body: some View {
    Form {
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

      Section {
        HStack(spacing: DS.controlGap) {
          DSStatusDot(status: monitor.indicator)
          VStack(alignment: .leading, spacing: 2) {
            Text(statusLine)
            if case .unreachable(let detail)? = monitor.lastError {
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
              await connection.apply(draft, secret: secret)
              isApplying = false
            }
          }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(draft.validationError != nil || isApplying)
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
      portText = String(connection.settings.port)
      secret = connection.savedSecret()
    }
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
    guard monitor.status == .connected else {
      return ConnectionStatusText.headline(status: monitor.status, error: monitor.lastError)
    }
    if monitor.catalog.isModelBrowsingDisabled {
      return String(localized: "header.model.browsingDisabled")
    }
    return String(format: String(localized: "prefs.dt.models"), monitor.catalog.models.count)
  }
}
