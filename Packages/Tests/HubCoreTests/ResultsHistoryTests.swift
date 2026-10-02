import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct ResultsHistoryTests {
  let job = GenerationJob(prompt: "p", model: "a.ckpt", parameters: GenerationParameters(steps: 4, seed: 9, randomSeed: false))
  let catalog = ModelCatalog(models: [CatalogModel(file: "a.ckpt", name: "A", family: "flux2_9b")], loras: [], fileCount: 1)

  func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ResultsHistoryTests-\(UUID())", isDirectory: true)
  }

  func entry(_ number: Int) -> ResultsHistoryEntry {
    ResultsHistoryEntry(path: "/x/\(number).png", date: Date(timeIntervalSince1970: Double(1_790_000_000 + number)))
  }

  /// A session over real PNG files, that has already run `count` images.
  func sessionWithResults(in root: URL, count: Int) async -> GenerationSession {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished((0..<count).map { _ in testImage(width: 40, height: 30) })])
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let session = GenerationSession(
      store: PNGImageStore(folder: root.appendingPathComponent("out")),
      history: ResultsHistoryStore(fileURL: root.appendingPathComponent("results.json")))
    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    return session
  }

  @Test func theStoreKeepsTheNewestFiftyInOrder() {
    let store = ResultsHistoryStore(fileURL: folder().appendingPathComponent("results.json"))
    store.save((0..<60).map(entry))
    let loaded = store.load()
    #expect(loaded.count == 50)
    #expect(loaded.first == entry(0))
    #expect(loaded.last == entry(49))
  }

  @Test func aMissingOrDamagedFileHasNoHistory() throws {
    let root = folder()
    let url = root.appendingPathComponent("results.json")
    #expect(ResultsHistoryStore(fileURL: url).load().isEmpty)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: url)
    #expect(ResultsHistoryStore(fileURL: url).load().isEmpty)
  }

  @Test func theResultsOfARunComeBackAtTheNextLaunch() async {
    let root = folder()
    let first = await sessionWithResults(in: root, count: 2)
    #expect(first.results.count == 2)
    let second = GenerationSession(
      store: PNGImageStore(folder: root.appendingPathComponent("out")),
      history: ResultsHistoryStore(fileURL: root.appendingPathComponent("results.json")))
    await second.restoreHistory()
    #expect(second.results.count == 2)
    #expect(second.results.allSatisfy { $0.isRestored && $0.job == job && $0.fileURL != nil })
    #expect(second.results.map(\.fileURL) == first.results.map(\.fileURL))
    #expect(second.results.allSatisfy { $0.image.width == 40 && $0.image.height == 30 })
  }

  @Test func theRestoredPicturesAreSmallAndTheNewestComeFirst() async throws {
    let root = folder()
    let out = root.appendingPathComponent("out")
    let store = PNGImageStore(folder: out)
    let big = testImage(width: 2000, height: 1000)
    let older = try store.save(big, job: job, index: 0, date: Date(timeIntervalSince1970: 1_790_000_000))
    let newer = try store.save(big, job: job, index: 0, date: Date(timeIntervalSince1970: 1_790_000_100))
    let history = ResultsHistoryStore(fileURL: root.appendingPathComponent("results.json"))
    history.save([
      ResultsHistoryEntry(path: newer.path, date: Date(timeIntervalSince1970: 1_790_000_100)),
      ResultsHistoryEntry(path: older.path, date: Date(timeIntervalSince1970: 1_790_000_000)),
    ])
    let session = GenerationSession(store: store, history: history)
    await session.restoreHistory()
    #expect(session.results.map(\.fileURL) == [newer, older])
    #expect(session.results.allSatisfy { max($0.image.width, $0.image.height) <= GenerationSession.restoredThumbnailSize })
  }

  @Test func filesThatAreGoneOrHaveNoJobAreSkipped() async throws {
    let root = folder()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let plain = root.appendingPathComponent("plain.png")
    try pictureData(width: 20, height: 20).write(to: plain)
    let good = try PNGImageStore(folder: root).save(testImage(), job: job, index: 0, date: Date())
    let history = ResultsHistoryStore(fileURL: root.appendingPathComponent("results.json"))
    history.save([
      ResultsHistoryEntry(path: root.appendingPathComponent("gone.png").path, date: Date()),
      ResultsHistoryEntry(path: plain.path, date: Date()),
      ResultsHistoryEntry(path: good.path, date: Date()),
    ])
    let session = GenerationSession(store: PNGImageStore(folder: root), history: history)
    await session.restoreHistory()
    #expect(session.results.map(\.fileURL) == [good])
  }

  @Test func aNewResultStaysAheadOfTheRestoredOnesAndIsNotListedTwice() async {
    let root = folder()
    _ = await sessionWithResults(in: root, count: 1)
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage(width: 40, height: 30)])])
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let session = GenerationSession(
      store: PNGImageStore(folder: root.appendingPathComponent("out")),
      history: ResultsHistoryStore(fileURL: root.appendingPathComponent("results.json")))
    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    await session.restoreHistory()
    await session.restoreHistory()
    #expect(session.results.count == 2)
    #expect(session.results.first?.isRestored == false)
    #expect(session.results.last?.isRestored == true)
    // And what is saved lists both.
    #expect(ResultsHistoryStore(fileURL: root.appendingPathComponent("results.json")).load().count == 2)
  }
}
