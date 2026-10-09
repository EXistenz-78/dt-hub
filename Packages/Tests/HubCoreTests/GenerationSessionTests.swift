import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

/// An `ImageStore` that keeps what it is asked to save, or fails on demand.
final class MemoryImageStore: ImageStore, @unchecked Sendable {
  private let lock = NSLock()
  private var saved: [(GenerationJob, Int)] = []
  private var savedElapsed: [TimeInterval?] = []
  private var trashedPaths: [String] = []
  let fails: Bool
  /// Paths the "Trash" refuses.
  let refusesToTrash: Set<String>

  init(fails: Bool = false, refusesToTrash: Set<String> = []) {
    self.fails = fails
    self.refusesToTrash = refusesToTrash
  }

  var count: Int { lock.withLock { saved.count } }
  var elapsedTimes: [TimeInterval?] { lock.withLock { savedElapsed } }
  var trashed: [String] { lock.withLock { trashedPaths } }

  func trash(_ url: URL) throws {
    if refusesToTrash.contains(url.path) { throw ImageStoreError.cannotTrash("refused") }
    lock.withLock { trashedPaths.append(url.path) }
  }

  func save(_ image: CGImage, job: GenerationJob, index: Int, date: Date, elapsed: TimeInterval?) throws -> URL {
    if fails { throw ImageStoreError.cannotWrite("disk full") }
    lock.withLock {
      saved.append((job, index))
      savedElapsed.append(elapsed)
    }
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

  @Test func everyImageKeepsTheTimeItTookAndTheStoreGetsIt() async {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage(), testImage()])], stepDelay: .milliseconds(200))
    let monitor = await connected(backend)
    let store = MemoryImageStore()
    let session = GenerationSession(store: store)
    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    #expect(session.results.count == 2)
    let times = session.results.compactMap(\.elapsed)
    #expect(times.count == 2)
    // Two images made in one call share its time: about 0.2 s in all, so about 0.1 s each.
    #expect(times.allSatisfy { $0 > 0.05 && $0 < 0.19 })
    #expect(store.elapsedTimes.compactMap { $0 }.count == 2)
  }

  @Test func aRestoredImageReadsItsTimeBackFromItsFile() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("elapsed-\(UUID())", isDirectory: true)
    let history = ResultsHistoryStore(fileURL: folder.appendingPathComponent("results.json"))
    let png = PNGImageStore(folder: folder)
    let url = try png.save(testImage(), job: job, index: 0, date: Date(), elapsed: 12.4)
    history.save([ResultsHistoryEntry(path: url.path, date: Date())])
    let session = GenerationSession(store: png, history: history)
    await session.restoreHistory()
    #expect(session.results.first?.elapsed == 12.4)
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
      [.progress(step: 3, totalSteps: 4), .preview(testImage()), .finished([testImage()])], gated: true)
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())

    session.start(job, backend: backend, monitor: monitor)
    await backend.release(2)  // the progress and the preview, not the end
    #expect(await eventually { session.phase == .running(step: 3, totalSteps: 4) && session.preview != nil })
    // However slow the machine, nothing moves without a release.
    try await Task.sleep(for: .milliseconds(300))
    #expect(session.phase == .running(step: 3, totalSteps: 4))
    await backend.release()
    await session.waitUntilFinished()
    #expect(session.phase == .idle)
  }

  @Test func pausesTheServerChecksWhileRunning() async throws {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])], gated: true)
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())

    session.start(job, backend: backend, monitor: monitor)
    #expect(monitor.isPaused)
    await backend.release()
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
    await backend.setGeneration([.finished([testImage()])], gated: true)
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())

    session.start([job, second(seed: 10)], backend: backend, monitor: monitor)
    #expect(session.batch == .init(index: 1, count: 2))
    await backend.release()  // the first batch ends
    #expect(await eventually { session.batch == .init(index: 2, count: 2) })
    await backend.release()
    await session.waitUntilFinished()
  }

  @Test func stopKeepsTheBatchesAlreadyFinished() async throws {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])], gated: true)
    let monitor = await connected(backend)
    let store = MemoryImageStore()
    let session = GenerationSession(store: store)

    session.start([job, second(seed: 10), second(seed: 11)], backend: backend, monitor: monitor)
    await backend.release()  // the first batch ends; the second is under way and held
    #expect(await eventually { await backend.jobs.count == 2 && session.results.count == 1 })
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

  @Test func aStoppedRunIsToldApartFromAFinishedOne() async throws {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.progress(step: 1, totalSteps: 4), .finished([testImage()])], stepDelay: .seconds(2))
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())
    #expect(!session.lastRunWasStopped)
    session.start(job, backend: backend, monitor: monitor)
    try await Task.sleep(for: .milliseconds(100))
    session.cancel()
    await session.waitUntilFinished()
    #expect(session.lastRunWasStopped)

    await backend.setGeneration([.finished([testImage()])])
    session.start(job, backend: backend, monitor: monitor)
    #expect(!session.lastRunWasStopped)  // cleared as the next RUN starts
    await session.waitUntilFinished()
    #expect(!session.lastRunWasStopped)
  }

  @Test func aFailedRunIsNotAStoppedOne() async {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])])
    await backend.failFromJob(1, with: .generationFailed("boom"))
    let monitor = await connected(backend)
    let session = GenerationSession(store: MemoryImageStore())
    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    #expect(!session.lastRunWasStopped)
    #expect(session.phase == .failed(.generationFailed("boom")))
  }
}
