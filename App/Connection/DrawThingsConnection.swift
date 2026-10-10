import AppKit
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
  /// The version of the gRPCServerCLI DT Hub starts and whether a newer one is out (checked at launch and on demand).
  private(set) var serverVersion = ServerVersionInfo.idle
  /// True when the last Apply could not save the shared secret in the Keychain.
  private(set) var secretSaveFailed = false

  @ObservationIgnored private let settingsStore = ConnectionSettingsStore()
  @ObservationIgnored private let managedStore = ManagedServerSettingsStore()
  @ObservationIgnored private let secretStore: any SecretStore = KeychainSecretStore()
  @ObservationIgnored private var loop: Task<Void, Never>?
  /// True while an image is being made or about to be (set by the app): the image model is
  /// never released then, whatever the language model asks.
  @ObservationIgnored var isImageWorkActive: @MainActor () -> Bool = { false }

  init() {
    settings = settingsStore.load()
    managed = managedStore.load()
    // Quitting stops the managed server whichever windows are open: this object lives as long
    // as the app, a window's view does not.
    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { [managedServer] _ in
      MainActor.assumeIsolated { managedServer.terminateNow() }
    }
    Task { await refreshServerVersion() }
    loop = Task {
      // Managed mode: the server starts with the app (spec §5).
      if managed.mode == .managed { await managedServer.start(managed) }
      await monitor.replaceBackend(makeBackend())
      await monitor.run()
    }
  }

  /// Looks at the program of the managed server (its sha256 against the releases on GitHub): one request, at launch,
  /// after Apply and when asked. Another mode has nothing to look at.
  func refreshServerVersion() async {
    guard managed.mode == .managed else {
      serverVersion = .idle
      return
    }
    serverVersion = ServerVersionInfo(state: .checking, installed: serverVersion.installed, latest: serverVersion.latest)
    let defaults = UserDefaults.standard
    let remembered = defaults.string(forKey: "drawThings.serverVersion.hash").flatMap { hash in
      defaults.string(forKey: "drawThings.serverVersion.tag").map { (hash: hash, tag: $0) }
    }
    let result = await ServerVersionChecker.live.check(programAt: managed.binaryPath, remembered: remembered)
    guard managed.mode == .managed else { return }
    serverVersion = result.info
    if let hash = result.hash, let tag = result.info.installed {
      defaults.set(hash, forKey: "drawThings.serverVersion.hash")
      defaults.set(tag, forKey: "drawThings.serverVersion.tag")
    }
  }

  /// The saved shared secret, empty when there is none.
  func savedSecret() -> String {
    secretStore.read() ?? ""
  }

  /// What the header dot shows: yellow while the managed server is starting (its first moments,
  /// until it answers: spec §7), whatever the monitor says meanwhile; after that a server that
  /// does not answer is red, with the reason.
  var indicator: ConnectionStatus {
    if releasedForLanguageModel { return .connecting }
    if managed.mode == .managed, managedServer.isStarting, monitor.status != .connected { return .connecting }
    return monitor.indicator
  }

  /// What to say when the server answers but lists no model: with "Model browsing" off (a
  /// server of the Draw Things app), or, for the server DT Hub starts (which always has
  /// it on), with no model file in the chosen folder.
  var noModelsText: String {
    managed.mode == .managed
      ? String(localized: "server.noModels") : String(localized: "header.model.browsingDisabled")
  }

  /// True while the managed server is stopped on purpose, to leave the memory to the language
  /// model (spec §9): the next RUN starts it again.
  private(set) var releasedForLanguageModel = false

  /// Why RUN cannot start now; nil when it can. A server parked for the language model is no
  /// reason: RUN brings it back.
  var runBlocker: RunBlocker? {
    if releasedForLanguageModel, selection.selectedFile != nil { return nil }
    return RunAvailability.blocker(
      connection: monitor.status, selectedModel: selection.selectedFile, catalog: monitor.catalog)
  }

  /// Stops the managed server so the language model has the room. Only the server DT Hub
  /// started can be stopped: Draw Things has no call to unload a model from another one.
  func releaseImageModel() async {
    guard managed.mode == .managed, managedServer.isRunning, !isImageWorkActive() else { return }
    // Marked first: a RUN pressed while the server is leaving must wait for it to come back.
    releasedForLanguageModel = true
    await managedServer.stopAndWait()
  }

  /// Brings the managed server back when it was released, and waits until it answers (the
  /// image model loads again, which takes time). It gives up when the server cannot start
  /// (the banner says why) or when the wait is cancelled (Stop).
  func ensureServerForRun() async {
    guard releasedForLanguageModel else { return }
    defer { releasedForLanguageModel = false }
    // The mode was changed while the server was parked: there is nothing to bring back.
    guard managed.mode == .managed else { return }
    await managedServer.start(managed)
    for _ in 0..<300 {
      if Task.isCancelled { return }
      switch managedServer.state {
      case .failedToStart, .exitedUnexpectedly: return
      case .stopped, .running: break
      }
      await monitor.refresh()
      if monitor.status == .connected { return }
      try? await Task.sleep(for: .seconds(1))
    }
  }

  /// Starts the managed server again (after it ended or failed).
  func restartManagedServer() async {
    guard managed.mode == .managed else { return }
    releasedForLanguageModel = false
    await managedServer.start(managed)
  }

  /// Saves the settings and the secret, starts or stops the managed server, then reconnects.
  func apply(_ newSettings: ConnectionSettings, secret: String, managed newManaged: ManagedServerSettings) async {
    settings = newSettings
    settingsStore.save(newSettings)
    // Applying starts or stops the server itself: nothing stays parked.
    releasedForLanguageModel = false
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
    await refreshServerVersion()
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
