import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

/// `GenerationSession.switchHistory`: the strip of results follows the project that is open.
@MainActor
struct GenerationSessionProjectTests {
  let catalog = ModelCatalog(
    models: [CatalogModel(file: "a.ckpt", name: "A", family: "flux2_9b")], loras: [], fileCount: 1)
  let job = GenerationJob(prompt: "p", model: "a.ckpt", parameters: GenerationParameters(steps: 4, seed: 9, randomSeed: false))

  private func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("switchHistory-\(UUID())", isDirectory: true)
  }

  private func history(_ root: URL, _ name: String) -> ResultsHistoryStore {
    ResultsHistoryStore(fileURL: root.appendingPathComponent("\(name)/results.json"))
  }

  /// A saved picture listed in `history`.
  private func savePicture(in root: URL, listedIn history: ResultsHistoryStore) throws {
    let url = try PNGImageStore(folder: root).save(testImage(), job: job, index: 0, date: Date(), elapsed: nil)
    history.save([ResultsHistoryEntry(path: url.path, date: Date())])
  }

  @Test func eachProjectShowsItsOwnStrip() async throws {
    let dir = root()
    let (a, b) = (history(dir, "a"), history(dir, "b"))
    try savePicture(in: dir, listedIn: a)
    let session = GenerationSession(store: PNGImageStore(folder: dir), history: a)
    await session.restoreHistory()
    #expect(session.results.count == 1)
    await session.switchHistory(to: b)
    #expect(session.results.isEmpty)
    #expect(a.load().count == 1)  // the first project's list is untouched
    await session.switchHistory(to: a)
    #expect(session.results.count == 1)
  }

  @Test func aRunIsListedInTheProjectItWasMadeIn() async throws {
    let dir = root()
    let (a, b) = (history(dir, "a"), history(dir, "b"))
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])])
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let session = GenerationSession(store: PNGImageStore(folder: dir), history: a)
    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    #expect(a.load().count == 1)
    await session.switchHistory(to: b)
    #expect(session.results.isEmpty)
    #expect(b.load().isEmpty)
    #expect(a.load().count == 1)
  }

  @Test func duringARunTheStripDoesNotSwitch() async throws {
    let dir = root()
    let (a, b) = (history(dir, "a"), history(dir, "b"))
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])], gated: true)
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let session = GenerationSession(store: PNGImageStore(folder: dir), history: a)
    session.start(job, backend: backend, monitor: monitor)
    #expect(session.isRunning)
    await session.switchHistory(to: b)
    await backend.release(10)
    await session.waitUntilFinished()
    #expect(a.load().count == 1)
    #expect(b.load().isEmpty)
    #expect(session.results.count == 1)
  }

  @Test func withoutAHistoryTheStripIsJustEmpty() async throws {
    let dir = root()
    let a = history(dir, "a")
    try savePicture(in: dir, listedIn: a)
    let session = GenerationSession(store: PNGImageStore(folder: dir), history: a)
    await session.restoreHistory()
    await session.switchHistory(to: nil)
    #expect(session.results.isEmpty)
  }
}
