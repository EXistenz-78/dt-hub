import DTBridge
import HubCore
import HubKit
import Observation

/// App-level wiring of the Draw Things link (spec §5): settings, the Keychain secret, the
/// connection monitor and the model selection. It starts checking the server when it is
/// created and keeps doing so for the life of the app, whatever windows are open.
@MainActor
@Observable
final class DrawThingsConnection {
  let monitor = ConnectionMonitor()
  let selection = ModelSelection()
  /// The gRPCServerCLI DT Hub starts in "managed" mode (spec §5).
  let managedServer = ManagedServer()
  private(set) var settings: ConnectionSettings
  private(set) var managed: ManagedServerSettings
  /// True when the last Apply could not save the shared secret in the Keychain.
  private(set) var secretSaveFailed = false

  @ObservationIgnored private let settingsStore = ConnectionSettingsStore()
  @ObservationIgnored private let managedStore = ManagedServerSettingsStore()
  @ObservationIgnored private let secretStore: any SecretStore = KeychainSecretStore()
  @ObservationIgnored private var loop: Task<Void, Never>?

  init() {
    settings = settingsStore.load()
    managed = managedStore.load()
    loop = Task {
      // Managed mode: the server starts with the app (spec §5).
      if managed.mode == .managed { await managedServer.start(managed) }
      await monitor.replaceBackend(makeBackend())
      await monitor.run()
    }
  }

  /// The saved shared secret, empty when there is none.
  func savedSecret() -> String {
    secretStore.read() ?? ""
  }

  /// What the header dot shows: yellow while the managed server is starting, until it answers
  /// (spec §7), whatever the monitor says meanwhile.
  var indicator: ConnectionStatus {
    if managed.mode == .managed, managedServer.isRunning, monitor.status != .connected { return .connecting }
    return monitor.indicator
  }

  /// What to say when the server answers but lists no model: with "Model browsing" off (a
  /// server of the Draw Things app), or, for the server DT Hub starts (which always has
  /// it on), with no model file in the chosen folder.
  var noModelsText: String {
    managed.mode == .managed
      ? String(localized: "server.noModels") : String(localized: "header.model.browsingDisabled")
  }

  /// Starts the managed server again (after it ended or failed).
  func restartManagedServer() async {
    guard managed.mode == .managed else { return }
    await managedServer.start(managed)
  }

  /// Saves the settings and the secret, starts or stops the managed server, then reconnects.
  func apply(_ newSettings: ConnectionSettings, secret: String, managed newManaged: ManagedServerSettings) async {
    settings = newSettings
    settingsStore.save(newSettings)
    managed = newManaged
    managedStore.save(newManaged)
    if newManaged.mode == .managed {
      await managedServer.start(newManaged)
    } else {
      await managedServer.stopAndWait()
    }
    do {
      try secretStore.write(secret)
      secretSaveFailed = false
    } catch {
      secretSaveFailed = true
    }
    await monitor.replaceBackend(makeBackend())
  }

  /// Managed mode talks to its own server: this Mac, its port, TLS, no shared secret (the
  /// server is started without one, and listens on this Mac only).
  private var effectiveSettings: ConnectionSettings {
    managed.mode == .managed ? ConnectionSettings(host: "127.0.0.1", port: managed.port, useTLS: true) : settings
  }

  private func makeBackend() -> (any GenerationBackend)? {
    let effective = effectiveSettings
    guard effective.validationError == nil else { return nil }
    return DrawThingsBackend(
      host: effective.trimmedHost, port: effective.port, useTLS: effective.useTLS,
      sharedSecret: managed.mode == .managed ? nil : secretStore.read())
  }
}
