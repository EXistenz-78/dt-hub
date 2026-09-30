import Foundation
import HubKit
import Testing

@testable import HubCore

struct PNGImageStoreTests {
  let job = GenerationJob(
    prompt: "a lighthouse at dusk", model: "flux_2_klein_9b_f16.ckpt",
    parameters: GenerationParameters(seed: 1234, randomSeed: false))
  let date = Date(timeIntervalSince1970: 1_790_000_000)

  func tempFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("PNGImageStoreTests-\(UUID())", isDirectory: true)
  }

  @Test func savesAPNGWithTheJobInside() throws {
    let store = PNGImageStore(folder: tempFolder())
    let url = try store.save(testImage(), job: job, index: 0, date: date)
    #expect(url.pathExtension == "png")
    #expect(url.lastPathComponent.hasSuffix("-1234.png"))
    #expect(PNGImageStore.job(in: url) == job)
  }

  @Test func namesEachImageOfABatchAndNeverOverwrites() throws {
    let store = PNGImageStore(folder: tempFolder())
    let first = try store.save(testImage(), job: job, index: 0, date: date)
    let second = try store.save(testImage(), job: job, index: 1, date: date)
    let again = try store.save(testImage(), job: job, index: 0, date: date)
    #expect(second.lastPathComponent.hasSuffix("-1234-2.png"))
    #expect(Set([first, second, again]).count == 3)
  }

  @Test func reportsAFolderItCannotCreate() {
    let store = PNGImageStore(folder: URL(fileURLWithPath: "/System/DT Hub test"))
    #expect(throws: ImageStoreError.self) { try store.save(testImage(), job: job, index: 0, date: date) }
  }
}
