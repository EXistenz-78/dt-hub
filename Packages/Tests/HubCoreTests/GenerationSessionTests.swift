import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

/// An `ImageStore` that keeps what it is asked to save, or fails on demand.
final class MemoryImageStore: ImageStore, @unchecked Sendable {
  private let lock = NSLock()
  private var saved: [(GenerationJob, Int)] = []
  let fails: Bool

  init(fails: Bool = false) { self.fails = fails }

  var count: Int { lock.withLock { saved.count } }

  func save(_ image: CGImage, job: GenerationJob, index: Int, date: Date) throws -> URL {
    if fails { throw ImageStoreError.cannotWrite("disk full") }
    lock.withLock { saved.append((job, index)) }
    return URL(fileURLWithPath: "/tmp/\(job.parameters.seed)-\(index).png")
  }
}

@MainActor
struct GenerationSessionTests {
  let catalog = ModelCatalog(
    models: [CatalogModel(file: "a.ckpt", name: "A", family: "flux2_9b")], loras: [], fileCount: 1)
  let job = GenerationJob(prompt: "p", model: "a.ckpt", parameters: GenerationParameters(steps: 4, seed: 9, randomSeed: false))

  func connected(_ backend: FakeBackend) async -> ConnectionMonitor {
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    return monitor
  }

  @Test func theBackendReceivesTheControlInputsOfEveryBatch() async {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])])
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())
    let start = testImage(width: 16, height: 16)
    session.start([job, job], inputs: GenerationInputs(image: start), backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    let received = await backend.inputs
    #expect(received.count == 2)
    #expect(received.allSatisfy { $0.image === start })
    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    #expect(await backend.inputs.last?.isEmpty == true)
  }

  @Test func aRunThatCannotStartCanBeReportedAsAFailure() {
    let session = GenerationSession(store: MemoryImageStore())
    session.fail(with: .generationFailed("The start image could not be read"))
    #expect(session.phase == .failed(.generationFailed("The start image could not be read")))
    #expect(!session.isRunning)
    session.dismissFailure()
    #expect(session.phase == .idle)
  }

  @Test func runsAGenerationAndKeepsTheSavedImages() async {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.progress(step: nil, totalSteps: 4), .progress(step: 2, totalSteps: 4), .finished([testImage(), testImage()])])
    let monitor = await connected(backend)
    let store = MemoryImageStore()
    let session = GenerationSession(store: store)

    session.start(job, backend: backend, monitor: monitor)
    #expect(session.isRunning)
    await session.waitUntilFinished()

    #expect(session.phase == .idle)
    #expect(session.results.count == 2)
    #expect(session.results.allSatisfy { $0.job == job && $0.fileURL != nil })
    #expect(store.count == 2)
    #expect(await backend.jobs == [job])
  }

  @Test func reportsProgressAndPreviewWhileRunning() async throws {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration(
      [.progress(step: 3, totalSteps: 4), .preview(testImage()), .finished([testImage()])], stepDelay: .milliseconds(150))
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())

    session.start(job, backend: backend, monitor: monitor)
    try await Task.sleep(for: .milliseconds(380))
    #expect(session.phase == .running(step: 3, totalSteps: 4))
    #expect(session.preview != nil)
    await session.waitUntilFinished()
  }

  @Test func pausesTheServerChecksWhileRunning() async throws {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])], stepDelay: .milliseconds(200))
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())

    session.start(job, backend: backend, monitor: monitor)
    #expect(monitor.isPaused)
    await session.waitUntilFinished()
    #expect(!monitor.isPaused)
  }

  @Test func aFailureIsShownAndChecksResume() async {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.progress(step: 1, totalSteps: 4)], error: .noImages)
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())

    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    #expect(session.phase == .failed(.noImages))
    #expect(!monitor.isPaused)
    session.dismissFailure()
    #expect(session.phase == .idle)
  }

  @Test func stopCancelsWithoutAnError() async throws {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.progress(step: 1, totalSteps: 4), .finished([testImage()])], stepDelay: .seconds(2))
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())

    session.start(job, backend: backend, monitor: monitor)
    try await Task.sleep(for: .milliseconds(100))
    session.cancel()
    await session.waitUntilFinished()
    #expect(session.phase == .idle)
    #expect(session.results.isEmpty)
    #expect(!monitor.isPaused)
  }

  @Test func aSecondRunWhileRunningIsIgnored() async {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])], stepDelay: .milliseconds(200))
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())

    session.start(job, backend: backend, monitor: monitor)
    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    #expect(await backend.jobs.count == 1)
  }

  @Test func anImageThatCannotBeSavedIsKeptWithTheReason() async {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])])
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore(fails: true))

    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    #expect(session.results.count == 1)
    #expect(session.results[0].fileURL == nil)
    #expect(session.results[0].saveError != nil)
  }

  @Test func runsTheBatchesOneAfterTheOther() async {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage(), testImage()])])
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())
    let batches = [job, second(seed: 10), second(seed: 11)]

    session.start(batches, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    #expect(await backend.jobs == batches)
    // Newest batch first, images of a batch in order, each with its own batch's job.
    #expect(session.results.map(\.job.parameters.seed) == [11, 11, 10, 10, 9, 9])
    #expect(session.phase == .idle)
  }

  @Test func reportsWhichBatchIsRunning() async throws {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])], stepDelay: .milliseconds(200))
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())

    session.start([job, second(seed: 10)], backend: backend, monitor: monitor)
    #expect(session.batch == .init(index: 1, count: 2))
    try await Task.sleep(for: .milliseconds(300))
    #expect(session.batch == .init(index: 2, count: 2))
    await session.waitUntilFinished()
  }

  @Test func stopKeepsTheBatchesAlreadyFinished() async throws {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])], stepDelay: .milliseconds(200))
    let monitor = await connected(backend)
    let store = MemoryImageStore()
    let session = GenerationSession(store: store)

    session.start([job, second(seed: 10), second(seed: 11)], backend: backend, monitor: monitor)
    try await Task.sleep(for: .milliseconds(300))
    session.cancel()
    await session.waitUntilFinished()
    #expect(session.phase == .idle)
    #expect(session.results.map(\.job.parameters.seed) == [9])
    #expect(store.count == 1)
    #expect(await backend.jobs.count == 2)
  }

  @Test func aFailureKeepsTheBatchesAlreadyFinished() async throws {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])])
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())
    await backend.failFromJob(2, with: .unreachable("gone"))

    session.start([job, second(seed: 10)], backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    #expect(session.phase == .failed(.unreachable("gone")))
    #expect(session.results.count == 1)
  }

  func second(seed: UInt32) -> GenerationJob {
    GenerationJob(prompt: "p", model: "a.ckpt", parameters: GenerationParameters(steps: 4, seed: seed, randomSeed: false))
  }

  @Test func newestRunComesFirst() async {
    let backend = FakeBackend(.success(catalog))
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())
    let second = GenerationJob(prompt: "q", model: "a.ckpt", parameters: GenerationParameters(seed: 10, randomSeed: false))

    await backend.setGeneration([.finished([testImage()])])
    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    session.start(second, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    #expect(session.results.map(\.job.prompt) == ["q", "p"])
  }
}
