import CoreGraphics
import HubKit

/// A `GenerationBackend` whose answers, delays and generation script the test controls.
actor FakeBackend: GenerationBackend {
  private var result: Result<ModelCatalog, BackendError>
  private let delay: Duration?
  private(set) var fetchCount = 0
  private(set) var didShutDown = false

  /// What `generate` streams: the updates, then an optional error, with a pause between each.
  private var script: [GenerationUpdate] = []
  private var scriptError: BackendError?
  private var stepDelay: Duration = .zero
  private(set) var jobs: [GenerationJob] = []

  init(_ result: Result<ModelCatalog, BackendError>, delay: Duration? = nil) {
    self.result = result
    self.delay = delay
  }

  func setResult(_ newResult: Result<ModelCatalog, BackendError>) {
    result = newResult
  }

  func setGeneration(_ updates: [GenerationUpdate], error: BackendError? = nil, stepDelay: Duration = .zero) {
    script = updates
    scriptError = error
    self.stepDelay = stepDelay
  }

  func fetchCatalog() async throws -> ModelCatalog {
    fetchCount += 1
    if let delay { try await Task.sleep(for: delay) }
    return try result.get()
  }

  nonisolated func generate(_ job: GenerationJob) -> AsyncThrowingStream<GenerationUpdate, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        let (updates, error, pause) = await self.start(job)
        do {
          for update in updates {
            try await Task.sleep(for: pause)
            continuation.yield(update)
          }
          if let error { throw error }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func start(_ job: GenerationJob) -> ([GenerationUpdate], BackendError?, Duration) {
    jobs.append(job)
    return (script, scriptError, stepDelay)
  }

  func shutdown() async {
    didShutDown = true
  }
}

/// A 1×1 image for scripted results.
func testImage(width: Int = 8, height: Int = 8) -> CGImage {
  let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(CGColor(red: 0.24, green: 0.78, blue: 0.78, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  return context.makeImage()!
}
