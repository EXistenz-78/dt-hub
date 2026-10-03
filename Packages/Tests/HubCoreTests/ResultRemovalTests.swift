import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

/// Moving results of the strip to the Trash.
@MainActor
struct ResultRemovalTests {
  let catalog = ModelCatalog(
    models: [CatalogModel(file: "a.ckpt", name: "A", family: "flux2_9b")], loras: [], fileCount: 1)
  let job = GenerationJob(prompt: "p", model: "a.ckpt", parameters: GenerationParameters(steps: 4, seed: 9, randomSeed: false))

  /// A finished RUN of three images (files /tmp/9-0.png, /tmp/9-1.png, /tmp/9-2.png; newest first in the strip).
  func session(store: MemoryImageStore = MemoryImageStore(), history: ResultsHistoryStore? = nil) async -> GenerationSession {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage(), testImage(), testImage()])])
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let session = GenerationSession(store: store, history: history)
    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    return session
  }

  @Test func removingMovesTheFilesToTheTrashAndKeepsTheRest() async throws {
    let store = MemoryImageStore()
    let session = await session(store: store)
    let ids = Set(session.results.prefix(2).map(\.id))
    let kept = session.results[2].id
    let failures = session.remove(ids)
    #expect(failures.isEmpty)
    #expect(session.results.map(\.id) == [kept])
    #expect(Set(store.trashed) == ["/tmp/9-0.png", "/tmp/9-1.png"])
  }

  @Test func anUnknownIdIsIgnored() async {
    let store = MemoryImageStore()
    let session = await session(store: store)
    #expect(session.remove([UUID()]).isEmpty)
    #expect(session.results.count == 3 && store.trashed.isEmpty)
  }

  @Test func anImageThatWasNeverSavedLeavesTheStripWithoutTouchingTheTrash() async {
    let store = MemoryImageStore(fails: true)
    let session = await session(store: store)
    #expect(session.results.allSatisfy { $0.fileURL == nil })
    #expect(session.remove(Set(session.results.map(\.id))).isEmpty)
    #expect(session.results.isEmpty && store.trashed.isEmpty)
  }

  @Test func aFileTheTrashRefusesStaysInTheStripAndIsReported() async {
    let store = MemoryImageStore(refusesToTrash: ["/tmp/9-1.png"])
    let session = await session(store: store)
    let failures = session.remove(Set(session.results.map(\.id)))
    #expect(failures.count == 1)
    #expect(session.results.map { $0.fileURL?.path } == ["/tmp/9-1.png"])
    #expect(Set(store.trashed) == ["/tmp/9-0.png", "/tmp/9-2.png"])
  }

  @Test func theHistoryFileForgetsWhatWasRemoved() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("ResultRemovalTests-\(UUID()).json")
    let history = ResultsHistoryStore(fileURL: file)
    let session = await session(history: history)
    #expect(Set(history.load().map(\.path)) == ["/tmp/9-0.png", "/tmp/9-1.png", "/tmp/9-2.png"])
    session.remove([session.results[1].id])
    #expect(Set(history.load().map(\.path)) == ["/tmp/9-0.png", "/tmp/9-2.png"])
  }
}
