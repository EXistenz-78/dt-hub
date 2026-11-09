import AppKit
import Foundation
import HubCore
import HubMCP
import Observation

/// The MCP server as the app runs it (spec 2026-11-08): owns the settings, the token, the server and the policy objects,
/// and keeps the server in step with the settings (off by default).
@MainActor
@Observable
final class RemoteControlModel {
  var settings: RemoteControlSettings {
    didSet {
      guard settings != oldValue else { return }
      store.save(settings)
      box.value = settings
      if settings.mode != oldValue.mode { registry.hostDidChange() }
      if settings.enabled != oldValue.enabled || settings.port != oldValue.port { reconcile() }
    }
  }
  private(set) var isRunning = false
  private(set) var listeningPort: UInt16?
  private(set) var lastError: String?
  private(set) var connectedClients = 0
  private(set) var token: String

  let consent = ConsentCoordinator()
  let ledger: BudgetLedger
  let jobs: JobTracker
  var callLog: CallLog { registry.callLog }

  @ObservationIgnored private let store = RemoteControlSettingsStore()
  @ObservationIgnored private let box: SettingsBox
  @ObservationIgnored private let tokens = TokenStore(storage: KeychainSecretStorage())
  @ObservationIgnored private let host: AppAgentHost
  @ObservationIgnored private let registry: ToolRegistry
  @ObservationIgnored private let server: MCPHTTPServer
  @ObservationIgnored private var reconciling = false
  @ObservationIgnored private var watchTask: Task<Void, Never>?

  @MainActor final class SettingsBox {
    var value: RemoteControlSettings
    init(_ value: RemoteControlSettings) { self.value = value }
  }

  init(
    generation: GenerationController, connection: DrawThingsConnection, queueStore: QueueStore, queueRunner: QueueRunner,
    languageModel: LanguageModelManager, plugins: PluginRegistry, projects: ProjectManager
  ) {
    let initial = RemoteControlSettingsStore().load()
    settings = initial
    let box = SettingsBox(initial)
    self.box = box
    token = tokens.token()
    host = AppAgentHost(
      generation: generation, connection: connection, queueStore: queueStore, queueRunner: queueRunner,
      languageModel: languageModel, plugins: plugins, projects: projects)
    let jobs = JobTracker()
    let ledger = BudgetLedger(settings: { box.value })
    self.jobs = jobs
    self.ledger = ledger
    let gate = ConsentGate(ledger: ledger, settings: { box.value }, prompter: consent)
    let context = ToolContext(
      host: host, settings: { box.value }, jobs: jobs, ledger: ledger, gate: gate,
      paths: {
        let roots = [generation.projectFolder, generation.outputFolder].compactMap { $0 }
          + box.value.allowedFolders.map { URL(fileURLWithPath: $0, isDirectory: true) }
        return PathPolicy(roots: roots)
      })
    registry = ToolRegistry(context: context)
    server = MCPHTTPServer(registry: registry, tokens: tokens)
    host.onJobEvent = { [jobs] in jobs.apply($0) }
    consent.onAuthoriseSession = { [ledger] in ledger.confirm() }
    server.onClientCountChanged = { [weak self] in self?.connectedClients = $0 }
    if initial.enabled { reconcile() }
  }

  // MARK: Actions

  func authorizeSession() { ledger.confirm() }

  func resetSession() {
    ledger.reset()
    callLog.clear()
  }

  func regenerateToken() { token = tokens.regenerate() }

  /// Stops the agent at once: Run and the queue stop, the clients are disconnected, the server goes off.
  func killSwitch() {
    host.stop()
    host.stopQueue()
    jobs.clientDisconnected()
    settings.enabled = false
  }

  var clientConfiguration: String {
    let port = settings.port
    return """
      {
        "mcpServers": {
          "dthub": {
            "url": "http://127.0.0.1:\(port)/mcp",
            "headers": { "Authorization": "Bearer \(token)" }
          }
        }
      }
      """
  }

  func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  // MARK: Keeping the server in step with the settings

  private func reconcile() {
    guard !reconciling else { return }
    reconciling = true
    Task { @MainActor in
      defer { reconciling = false }
      while true {
        let wanted = settings.enabled
        let port = settings.port
        if isRunning, !wanted || listeningPort != port {
          await server.stop()
          isRunning = false
          listeningPort = nil
          watchTask?.cancel()
        }
        if wanted, !isRunning {
          do {
            try await server.start(port: port)
            isRunning = true
            listeningPort = port
            lastError = nil
            startWatching()
          } catch MCPServerError.portInUse(let busy) {
            lastError = String(localized: "remote.error.portInUse").replacingOccurrences(of: "%d", with: "\(busy)")
          } catch {
            lastError = "\(error)"
          }
        }
        // Settings may have changed while the server was starting or stopping.
        if settings.enabled == isRunning && (!isRunning || listeningPort == settings.port) { break }
        if lastError != nil && !isRunning { break }
      }
    }
  }

  /// The list of tools depends on the model (specialist language models); the user may change it in the app.
  private func startWatching() {
    watchTask?.cancel()
    watchTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        self?.registry.hostDidChange()
      }
    }
  }
}
