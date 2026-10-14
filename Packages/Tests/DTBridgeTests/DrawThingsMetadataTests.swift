import CoreGraphics
import Foundation
import HubCore
import HubKit
import ImageIO
import Testing

@testable import DTBridge

struct DrawThingsMetadataTests {
  var job: GenerationJob {
    var parameters = GenerationParameters(width: 2048, height: 1792, steps: 40)
    parameters.seed = 2_140_239_989
    parameters.guidanceScale = 1
    parameters.shift = 1
    parameters.sampler = .ddimTrailing
    parameters.loras = [LoRASelection(file: "x_lora_f16.ckpt", weight: 0.8, trigger: "xx")]
    return GenerationJob(
      prompt: "a cat", negativePrompt: "blurry", model: "qwen_image_2.1_q8p.ckpt", parameters: parameters,
      imageStrength: 0.6, moodboardCount: 2)
  }

  func object(_ text: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
  }

  @Test func theCommentHasTheKeysOfDrawThings() throws {
    let comment = try object(DrawThingsMetadata.comment(for: job, elapsed: 12.5))
    #expect(comment["c"] as? String == "xx a cat")
    #expect(comment["uc"] as? String == "blurry")
    #expect(comment["seed"] as? Int == 2_140_239_989)
    #expect(comment["steps"] as? Int == 40)
    #expect(comment["sampler"] as? String == "DDIM Trailing")
    #expect(comment["scale"] as? Double == 1)
    #expect(comment["shift"] as? Double == 1)
    #expect(comment["size"] as? String == "2048x1792")
    #expect(comment["model"] as? String == "qwen_image_2.1_q8p.ckpt")
    #expect(comment["strength"] as? Double == 0.6)
    #expect(comment["seed_mode"] as? String == "Scale Alike")
  }

  @Test func v2IsTheConfigurationOfDrawThings() throws {
    let v2 = try #require(try object(DrawThingsMetadata.comment(for: job, elapsed: nil))["v2"] as? [String: Any])
    #expect(v2["width"] as? Int == 2048 && v2["height"] as? Int == 1792 && v2["steps"] as? Int == 40)
    #expect(v2["model"] as? String == "qwen_image_2.1_q8p.ckpt" && v2["seed"] as? Int == 2_140_239_989)
  }

  @Test func theDataOfDTHubGoUnderTheirOwnKey() throws {
    let dthub = try #require(try object(DrawThingsMetadata.comment(for: job, elapsed: 12.5))["dthub"] as? [String: Any])
    #expect(dthub["prompt"] as? String == "a cat" && dthub["moodboardCount"] as? Int == 2)
    #expect(dthub["elapsedSeconds"] as? Double == 12.5)
    #expect(try object(DrawThingsMetadata.comment(for: job, elapsed: nil))["dthub"].flatMap { $0 as? [String: Any] }?["elapsedSeconds"] == nil)
  }

  func image() -> CGImage {
    CGContext(
      data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
  }

  func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("dtmeta-\(UUID())", isDirectory: true) }

  @Test func dtHubReadsBackTheJobAndTheTimeFromTheNewFormat() throws {
    let store = PNGImageStore(folder: folder(), metadata: DrawThingsMetadata.comment)
    let url = try store.save(image(), job: job, index: 0, date: Date(), elapsed: 12.5)
    #expect(PNGImageStore.job(in: url) == job)
    #expect(PNGImageStore.elapsed(in: url) == 12.5)
    #expect(try object(try #require(PNGImageStore.comment(in: url)))["c"] as? String == "xx a cat")
  }

  @Test func andStillReadsTheOldFormat() throws {
    let url = try PNGImageStore(folder: folder()).save(image(), job: job, index: 0, date: Date(), elapsed: 3)
    #expect(try object(try #require(PNGImageStore.comment(in: url)))["c"] == nil)
    #expect(PNGImageStore.job(in: url) == job && PNGImageStore.elapsed(in: url) == 3)
  }
}
