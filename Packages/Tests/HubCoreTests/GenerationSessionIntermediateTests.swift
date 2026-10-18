import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing

@testable import HubCore

@MainActor
struct GenerationSessionIntermediateTests {
  let catalog = ModelCatalog(
    models: [CatalogModel(file: "a.ckpt", name: "A", family: "flux2_9b")], loras: [], fileCount: 1)
  let job = GenerationJob(prompt: "p", model: "a.ckpt", parameters: GenerationParameters(steps: 4, seed: 9, randomSeed: false))

  func connected(_ backend: FakeBackend) async -> ConnectionMonitor {
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    return monitor
  }

  @Test func anIntermediateResultGoesToItsFileAndNotToTheStripOrTheStore() async throws {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage(width: 32, height: 16)])])
    let monitor = await connected(backend)
    let store = MemoryImageStore()
    let session = GenerationSession(store: store)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("intermediate-\(UUID()).png")
    defer { try? FileManager.default.removeItem(at: url) }
    session.start([job], backend: backend, monitor: monitor, intermediate: url)
    await session.waitUntilFinished()
    #expect(session.results.isEmpty)
    #expect(store.count == 0)
    #expect(session.intermediateResult == IntermediateResult(url: url, width: 32, height: 16))
    let written = try #require(PNGImageStore.image(at: url, maxPixel: 4096))
    #expect(written.width == 32 && written.height == 16)
  }

  @Test func aNormalRunIsUnchangedAndClearsTheIntermediateResult() async throws {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])])
    let monitor = await connected(backend)
    let store = MemoryImageStore()
    let session = GenerationSession(store: store)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("intermediate-\(UUID()).png")
    defer { try? FileManager.default.removeItem(at: url) }
    session.start([job], backend: backend, monitor: monitor, intermediate: url)
    await session.waitUntilFinished()
    session.start([job], backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    #expect(session.results.count == 1 && store.count == 1)
    #expect(session.intermediateResult == nil)
  }

  @Test func aFinishedPictureIsAdoptedIntoTheStripAndTheStore() async throws {
    let store = MemoryImageStore()
    let session = GenerationSession(store: store)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("adopt-\(UUID()).png")
    defer { try? FileManager.default.removeItem(at: url) }
    let image = testImage(width: 48, height: 32)
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    try (data as Data).write(to: url)
    let adopted = await session.adopt(fileAt: url, job: job)
    #expect(adopted)
    #expect(session.results.count == 1 && store.count == 1)
    #expect(session.results.first?.job.prompt == "p")
    #expect(session.results.first?.fileURL != nil)
    #expect(!(await session.adopt(fileAt: url.appendingPathExtension("missing"), job: job)), "an unreadable file adds nothing")
    #expect(session.results.count == 1)
  }
}
