import HubKit

/// The words for the connection state, shared by the header dot and the Preferences.
enum ConnectionStatusText {
  static func headline(status: ConnectionStatus, error: BackendError?) -> String {
    switch status {
    case .connected: String(localized: "status.connected")
    case .connecting: String(localized: "status.connecting")
    case .disconnected:
      error == .unauthorized
        ? String(localized: "status.unauthorized") : String(localized: "status.disconnected")
    }
  }
}
