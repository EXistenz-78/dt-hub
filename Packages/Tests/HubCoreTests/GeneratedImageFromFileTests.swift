import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import HubCore

struct GeneratedImageFromFileTests {
  private func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("gfile-\(UUID().uuidString)", isDirectory: true)
  }

  @Test func buildsFromAnImageSavedByTheStore() throws {
    let root = folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let job = GenerationJob(prompt: "una luna", model: "m.ckpt", parameters: GenerationParameters(seed: 7, randomSeed: false))
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let url = try PNGImageStore(folder: root).save(testImage(width: 64, height: 32), job: job, index: 0, date: date, elapsed: 12)
    let image = try #require(GeneratedImage.fromFile(url, date: date, maxPixel: 16))
    #expect(image.job.prompt == "una luna" && image.job.parameters.seed == 7)
    #expect(image.fileURL == url && image.isRestored && image.elapsed == 12)
    #expect(max(image.image.width, image.image.height) <= 16)
  }

  @Test func nilForAPNGWithoutAJob() throws {
    let root = folder()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("plain.png")
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, testImage(), nil)
    #expect(CGImageDestinationFinalize(destination))
    #expect(GeneratedImage.fromFile(url, date: .now, maxPixel: 64) == nil)
  }
}
