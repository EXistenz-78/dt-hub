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

  @Test func readsAPictureWrittenByDrawThingsItself() throws {
    let root = folder()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("dt.png")
    let comment = """
      {"c":"a fox","uc":"blurry","seed":42,"steps":20,"sampler":"DDIM Trailing","scale":4.5,"shift":3,\
      "size":"1024x768","model":"flux.ckpt","strength":0.7,"lora":[{"file":"x_lora_f16.ckpt","weight":0.8}],\
      "v2":{"width":1024,"height":768}}
      """
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(
      destination, testImage(),
      [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: comment]] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let job = try #require(PNGImageStore.job(in: url))
    #expect(job.prompt == "a fox" && job.negativePrompt == "blurry" && job.model == "flux.ckpt")
    #expect(job.parameters.seed == 42 && job.parameters.steps == 20 && job.parameters.sampler == .ddimTrailing)
    #expect(job.parameters.width == 1024 && job.parameters.height == 768 && job.parameters.guidanceScale == 4.5)
    #expect(job.parameters.loras.first?.file == "x_lora_f16.ckpt" && job.imageStrength == 0.7)
  }
}
