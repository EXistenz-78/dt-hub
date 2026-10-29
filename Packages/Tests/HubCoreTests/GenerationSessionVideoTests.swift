import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct GenerationSessionVideoTests {
  let catalog = ModelCatalog(
    models: [CatalogModel(file: "a.ckpt", name: "A", family: "ltx2")], loras: [], fileCount: 1)

  var job: GenerationJob {
    var parameters = GenerationParameters(steps: 4, seed: 9, randomSeed: false)
    parameters.video.numFrames = 5
    return GenerationJob(prompt: "p", model: "a.ckpt", parameters: parameters, videoFPS: 24)
  }

  func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("video-session-\(UUID())", isDirectory: true)
  }

  func clip(partial: Bool = false) -> GeneratedVideo {
    GeneratedVideo(
      frames: (0..<5).map { _ in testImage(width: 64, height: 64) }, audio: nil, framesPerSecond: 24, isPartial: partial)
  }

  func run(_ video: GeneratedVideo, in root: URL, history: ResultsHistoryStore? = nil) async -> GenerationSession {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finishedVideo(video)])
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let session = GenerationSession(store: PNGImageStore(folder: root), history: history)
    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    return session
  }

  @Test func finishedVideoAddsOneResultWithVideoURL() async throws {
    let session = await run(clip(), in: folder())
    #expect(session.results.count == 1)
    let result = try #require(session.results.first)
    let url = try #require(result.videoURL)
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(FileManager.default.fileExists(atPath: try #require(result.fileURL).path))
    #expect(abs(try #require(result.videoSeconds) - 5.0 / 24.0) < 0.001)
    #expect(!result.isPartialVideo)
    #expect(result.saveError == nil)
  }

  @Test func partialVideoIsMarked() async throws {
    let session = await run(clip(partial: true), in: folder())
    #expect(session.results.first?.isPartialVideo == true)
  }

  @Test func restoredVideoKeepsItsURL() async throws {
    let root = folder()
    let history = ResultsHistoryStore(fileURL: root.appendingPathComponent("results.json"))
    let first = await run(clip(), in: root, history: history)
    let mp4 = try #require(first.results.first?.videoURL)

    let second = GenerationSession(store: PNGImageStore(folder: root), history: history)
    await second.restoreHistory()
    let restored = try #require(second.results.first)
    #expect(restored.videoURL == mp4)
    #expect(abs(try #require(restored.videoSeconds) - 5.0 / 24.0) < 0.001)

    try FileManager.default.removeItem(at: mp4)
    let third = GenerationSession(store: PNGImageStore(folder: root), history: history)
    await third.restoreHistory()
    #expect(third.results.count == 1)
    #expect(third.results.first?.videoURL == nil)
  }

  @Test func removingAVideoTrashesBothFiles() async throws {
    let store = TrashRecordingStore(PNGImageStore(folder: folder()))
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finishedVideo(clip())])
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let session = GenerationSession(store: store)
    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    let result = try #require(session.results.first)
    let poster = try #require(result.fileURL)
    let mp4 = try #require(result.videoURL)
    #expect(session.remove([result.id]).isEmpty)
    #expect(session.results.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: poster.path))
    #expect(!FileManager.default.fileExists(atPath: mp4.path))
  }
}

/// A `PNGImageStore` whose "Trash" deletes, so a test can run without touching the real Trash.
struct TrashRecordingStore: ImageStore {
  let inner: PNGImageStore
  init(_ inner: PNGImageStore) { self.inner = inner }

  func save(_ image: CGImage, job: GenerationJob, index: Int, date: Date, elapsed: TimeInterval?) throws -> URL {
    try inner.save(image, job: job, index: index, date: date, elapsed: elapsed)
  }

  func trash(_ url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    if url.pathExtension.lowercased() == "png" { try? FileManager.default.removeItem(at: PNGImageStore.videoURL(forPoster: url)) }
  }
}
