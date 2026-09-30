/// Why the Draw Things server could not be used.
public enum BackendError: Error, Equatable, Sendable {
  /// The server wants a shared secret, or rejected the one sent.
  case unauthorized
  /// The server could not be reached; the detail is the underlying error, for display.
  case unreachable(String)
}

/// The generation server as HubCore sees it (spec §4). DTBridge implements it with gRPC;
/// tests use a fake. M3 adds generation.
public protocol GenerationBackend: Sendable {
  /// Asks the server what it has installed. Doubles as the connection check.
  func fetchCatalog() async throws -> ModelCatalog
  /// Closes the connection. The backend is not used afterwards.
  func shutdown() async
}
