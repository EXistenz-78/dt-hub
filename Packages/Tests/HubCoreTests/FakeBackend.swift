import CoreGraphics
import HubKit

/// A `GenerationBackend` whose answers, delays and generation script the test controls.
actor FakeBackend: GenerationBackend {
  private var result: Result<ModelCatalog, BackendError>
  private var delay: Duration?
  private(set) var fetchCount = 0
  private(set) var didShutDown = false

  /// What `generate` streams: the updates, then an optional error, with a pause between each.
  private var script: [GenerationUpdate] = []
  private var scriptError: BackendError?
  private var stepDelay: Duration = .zero
  /// With `gated`, an update goes out only when the test lets it (`release`), whatever the time:
  /// a test that must look at the state between two updates never races a clock.
  private var gated = false
  private var permits = 0
  private(set) var jobs: [GenerationJob] = []
  private(set) var inputs: [GenerationInputs] = []
  /// From this job on (1-based), `generate` fails at once with `failure`.
  private var failFrom: (job: Int, error: BackendError)?

  init(_ result: Result<ModelCatalog, BackendError>, delay: Duration? = nil) {
    self.result = result
    self.delay = delay
  }

  func setDelay(_ newDelay: Duration?) {
    delay = newDelay
  }

  func setResult(_ newResult: Result<ModelCatalog, BackendError>) {
    result = newResult
  }

  func setGeneration(
    _ updates: [GenerationUpdate], error: BackendError? = nil, stepDelay: Duration = .zero, gated: Bool = false
  ) {
    script = updates
    scriptError = error
    self.stepDelay = stepDelay
    self.gated = gated
    permits = 0
  }

  /// Lets `count` more updates of a gated generation go out (across all its batches).
  func release(_ count: Int = 1) {
    permits += count
  }

  /// Waits for a permit, polling so that a cancelled generation stops waiting.
  fileprivate func takePermit() async throws {
    while permits == 0 { try await Task.sleep(for: .milliseconds(2)) }
    permits -= 1
  }

  func failFromJob(_ number: Int, with error: BackendError) {
    failFrom = (number, error)
  }

  func fetchCatalog() async throws -> ModelCatalog {
    fetchCount += 1
    if let delay { try await Task.sleep(for: delay) }
    return try result.get()
  }

  nonisolated func generate(_ job: GenerationJob, inputs: GenerationInputs) -> AsyncThrowingStream<GenerationUpdate, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        let (updates, error, pause, gated) = await self.start(job, inputs: inputs)
        do {
          for update in updates {
            if gated { try await self.takePermit() } else { try await Task.sleep(for: pause) }
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

  private func start(_ job: GenerationJob, inputs: GenerationInputs) -> ([GenerationUpdate], BackendError?, Duration, Bool) {
    jobs.append(job)
    self.inputs.append(inputs)
    if let failFrom, jobs.count >= failFrom.job { return ([], failFrom.error, .zero, false) }
    return (script, scriptError, stepDelay, gated)
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

/// Waits, polling, until `condition` holds (5 seconds at most) and says whether it did: a state the
/// code reaches in its own time, with no fixed pause to guess.
@MainActor
func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
  for _ in 0..<1000 {
    if await condition() { return true }
    try? await Task.sleep(for: .milliseconds(5))
  }
  return await condition()
}
