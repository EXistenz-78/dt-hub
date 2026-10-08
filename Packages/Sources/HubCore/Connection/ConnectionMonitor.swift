import HubKit
import Observation

/// Keeps the link to Draw Things: status for the header dot, the model catalog, the last
/// error (spec §7, §10). The backend is replaced when the connection settings change.
@MainActor
@Observable
public final class ConnectionMonitor {
  public private(set) var status: ConnectionStatus = .disconnected
  /// What the server reports, as it is.
  public private(set) var serverCatalog: ModelCatalog = .empty
  /// What the app uses: the server's catalog with the user's LoRA trigger words and weights (`loraOverrides`).
  public private(set) var catalog: ModelCatalog = .empty
  /// The user's own LoRA trigger words and weights; changing them rebuilds `catalog` at once and calls
  /// `saveLoRAOverrides`.
  public var loraOverrides = LoRAOverrides() {
    didSet {
      rebuildCatalog()
      saveLoRAOverrides?(loraOverrides)
    }
  }
  @ObservationIgnored public var saveLoRAOverrides: ((LoRAOverrides) -> Void)?
  public private(set) var lastError: BackendError?

  /// What the status dot shows: yellow ("connecting") also when the server answers but has
  /// "Model browsing" off, because nothing can be generated until it is turned on.
  public var indicator: ConnectionStatus {
    status == .connected && catalog.isModelBrowsingDisabled ? .connecting : status
  }

  /// How often the server is checked, connected or not.
  public static let defaultInterval: Duration = .seconds(5)

  /// The backend in use, for generation (spec §4: HubCore talks to DT only through it).
  public private(set) var backend: (any GenerationBackend)?
  /// True while a generation runs: checks are skipped, so a slow check during a long model
  /// load cannot turn the dot red or empty the catalog mid-run.
  public private(set) var isPaused = false
  /// Bumped on every backend change, so a reply from a replaced backend is dropped.
  @ObservationIgnored private var generation = 0

  public init() {}

  /// Uses a new backend (nil when the settings are invalid): shuts the old one down,
  /// forgets its catalog and connects with the new one.
  public func replaceBackend(_ newBackend: (any GenerationBackend)?) async {
    let old = backend
    backend = newBackend
    generation += 1
    status = .disconnected
    setServerCatalog(.empty)
    lastError = nil
    await old?.shutdown()
    await refresh()
  }

  private func setServerCatalog(_ newCatalog: ModelCatalog) {
    serverCatalog = newCatalog
    rebuildCatalog()
  }

  private func rebuildCatalog() {
    let merged = loraOverrides.apply(to: serverCatalog)
    if catalog != merged { catalog = merged }
  }

  /// Asks the server for its catalog once. Shows "connecting" only when not already
  /// connected, so a periodic check does not make the dot blink.
  public func refresh() async {
    guard !isPaused else { return }
    guard let backend else {
      status = .disconnected
      setServerCatalog(.empty)
      return
    }
    let requestGeneration = generation
    if status != .connected { status = .connecting }
    do {
      let newCatalog = try await backend.fetchCatalog()
      guard requestGeneration == generation else { return }
      if serverCatalog != newCatalog { setServerCatalog(newCatalog) }
      status = .connected
      lastError = nil
    } catch {
      guard requestGeneration == generation else { return }
      status = .disconnected
      setServerCatalog(.empty)
      lastError = error as? BackendError ?? .unreachable(String(describing: error))
    }
  }

  /// Stops the periodic checks until `resume()`; a check already on its way is ignored
  /// (a busy server must not turn the dot red during a RUN).
  public func pause() {
    isPaused = true
    generation += 1
  }

  public func resume() {
    isPaused = false
  }

  /// Checks the server every `interval` until the calling task is cancelled
  /// (spec §10: automatic periodic reconnection).
  public func run(
    every interval: Duration = defaultInterval,
    sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) async {
    while true {
      do { try await sleep(interval) } catch { return }
      await refresh()
    }
  }
}
