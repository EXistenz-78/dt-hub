import HubKit

/// A `GenerationBackend` whose answer and delay the test controls.
actor FakeBackend: GenerationBackend {
  private var result: Result<ModelCatalog, BackendError>
  private let delay: Duration?
  private(set) var fetchCount = 0
  private(set) var didShutDown = false

  init(_ result: Result<ModelCatalog, BackendError>, delay: Duration? = nil) {
    self.result = result
    self.delay = delay
  }

  func setResult(_ newResult: Result<ModelCatalog, BackendError>) {
    result = newResult
  }

  func fetchCatalog() async throws -> ModelCatalog {
    fetchCount += 1
    if let delay { try await Task.sleep(for: delay) }
    return try result.get()
  }

  func shutdown() async {
    didShutDown = true
  }
}
