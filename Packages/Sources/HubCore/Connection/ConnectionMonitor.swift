import HubKit
import Observation

/// Keeps the link to Draw Things: status for the header dot, the model catalog, the last
/// error (spec §7, §10). The backend is replaced when the connection settings change.
@MainActor
@Observable
public final class ConnectionMonitor {
  public private(set) var status: ConnectionStatus = .disconnected
  public private(set) var catalog: ModelCatalog = .empty
  public private(set) var lastError: BackendError?

  /// How often the server is checked, connected or not.
  public static let defaultInterval: Duration = .seconds(5)

  @ObservationIgnored private var backend: (any GenerationBackend)?
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
    catalog = .empty
    lastError = nil
    await old?.shutdown()
    await refresh()
  }

  /// Asks the server for its catalog once. Shows "connecting" only when not already
  /// connected, so a periodic check does not make the dot blink.
  public func refresh() async {
    guard let backend else {
      status = .disconnected
      catalog = .empty
      return
    }
    let requestGeneration = generation
    if status != .connected { status = .connecting }
    do {
      let newCatalog = try await backend.fetchCatalog()
      guard requestGeneration == generation else { return }
      if catalog != newCatalog { catalog = newCatalog }
      status = .connected
      lastError = nil
    } catch {
      guard requestGeneration == generation else { return }
      status = .disconnected
      catalog = .empty
      lastError = error as? BackendError ?? .unreachable(String(describing: error))
    }
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
