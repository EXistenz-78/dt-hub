/// Why the Draw Things server could not be used.
public enum BackendError: Error, Equatable, Sendable {
  /// The server wants a shared secret, or rejected the one sent.
  case unauthorized
  /// The server could not be reached; the detail is the underlying error, for display.
  case unreachable(String)
  /// The generation ended without any image, even if the server said OK (spec §10).
  case noImages
  /// The server failed the generation; the detail is its message, for display.
  case generationFailed(String)
}

/// The generation server as HubCore sees it (spec §4). DTBridge implements it with gRPC;
/// tests use a fake.
public protocol GenerationBackend: Sendable {
  /// Asks the server what it has installed. Doubles as the connection check.
  func fetchCatalog() async throws -> ModelCatalog
  /// Runs one generation, with the images of the Control tab. Cancelling the consuming task
  /// cancels it on the server. The stream ends with `.finished` or throws a `BackendError`.
  func generate(_ job: GenerationJob, inputs: GenerationInputs) -> AsyncThrowingStream<GenerationUpdate, any Error>
  /// Closes the connection. The backend is not used afterwards.
  func shutdown() async
}

extension GenerationBackend {
  /// A text-to-image RUN, without the Control tab's images.
  public func generate(_ job: GenerationJob) -> AsyncThrowingStream<GenerationUpdate, any Error> {
    generate(job, inputs: .none)
  }
}
