import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

/// A saved result is kept in memory for the strip at the size the screen needs, not at the 8192 pixels
/// the Tiled Diffusion can make: a few of those would fill the memory Draw Things shares.
@MainActor
struct LargeResultTests {
  let catalog = ModelCatalog(
    models: [CatalogModel(file: "a.ckpt", name: "A", family: "flux2_9b")], loras: [], fileCount: 1)
  let job = GenerationJob(prompt: "p", model: "a.ckpt", parameters: GenerationParameters(steps: 4, seed: 9, randomSeed: false))

  func run(_ image: CGImage, store: MemoryImageStore) async -> GeneratedImage? {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([image])])
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let session = GenerationSession(store: store)
    session.start(job, backend: backend, monitor: monitor)
    await session.waitUntilFinished()
    return session.results.first
  }

  @Test func aSavedImageOverTheDisplaySizeIsKeptReduced() async throws {
    let result = try #require(await run(testImage(width: 3000, height: 1500), store: MemoryImageStore()))
    #expect(result.fileURL != nil)
    #expect(result.image.width == 2048 && result.image.height == 1024)
  }

  @Test func aTallImageIsReducedOnItsLongSide() async throws {
    let result = try #require(await run(testImage(width: 1000, height: 4000), store: MemoryImageStore()))
    #expect(result.image.width == 512 && result.image.height == 2048)
  }

  @Test func aSmallImageIsKeptAsItIs() async throws {
    let image = testImage(width: 1024, height: 768)
    let result = try #require(await run(image, store: MemoryImageStore()))
    #expect(result.image === image)
  }

  @Test func anImageThatCouldNotBeSavedIsKeptWhole() async throws {
    let result = try #require(await run(testImage(width: 3000, height: 1500), store: MemoryImageStore(fails: true)))
    #expect(result.fileURL == nil)
    #expect(result.image.width == 3000 && result.image.height == 1500)
  }
}
