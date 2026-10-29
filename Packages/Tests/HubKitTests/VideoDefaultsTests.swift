import Testing

@testable import HubKit

struct VideoDefaultsTests {
  @Test func fastH3Defaults() throws {
    let result = try #require(
      VideoDefaults.applying(to: GenerationParameters(), file: "fasth3_omni_i4x.ckpt", family: "minimax_h3"))
    #expect(result.steps == 8)
    #expect(result.sampler == .ddimTrailing)
    #expect(result.guidanceScale == 1)
    #expect(result.shift == 12)
    #expect(result.resolutionDependentShift == false)
    #expect(result.width == 832)
    #expect(result.height == 512)
    #expect(result.video.numFrames == 124)
    #expect(result.video.shiftForAudio == 3)
    #expect(result.advanced.tiledDecoding == true)
    #expect(result.advanced.decodingTileWidth == 256)
    #expect(result.advanced.decodingTileHeight == 256)
    #expect(result.advanced.decodingTileOverlap == 64)
    #expect(result.batchSize == 1)
  }

  @Test func h3Defaults() throws {
    let result = try #require(
      VideoDefaults.applying(to: GenerationParameters(), file: "minimax_h3_ref2va_i4x.ckpt", family: "minimax_h3"))
    #expect(result.steps == 50)
    #expect(result.sampler == .ddimTrailing)
    #expect(result.shift == 12)
    #expect(result.width == 576)
    #expect(result.height == 448)
    #expect(result.video.numFrames == 56)
    #expect(result.advanced.tiledDecoding == true)
  }

  @Test func ltxDefaults() throws {
    let result = try #require(
      VideoDefaults.applying(to: GenerationParameters(), file: "ltx_2.3_22b_distilled_1.1_q8p.ckpt", family: "ltx2.3"))
    #expect(result.steps == 8)
    #expect(result.sampler == .tcdTrailing)
    #expect(result.guidanceScale == 1)
    #expect(result.shift == 5)
    #expect(result.video.numFrames == 121)
    #expect(result.width == 1280)
    #expect(result.height == 768)
    #expect(result.advanced.hiresFix == true)
    #expect(result.advanced.hiresFixWidth == 640)
    #expect(result.advanced.hiresFixHeight == 384)
    #expect(result.advanced.hiresFixStrength == 0.7)
    #expect(result.batchSize == 1)
  }

  @Test func resetsAcceleratorsForVideoFamilies() throws {
    var start = GenerationParameters()
    start.video.usesSolAttention = true
    start.advanced.teaCache = true
    for (file, family) in [("fasth3_omni_i4x.ckpt", "minimax_h3"), ("ltx_2.3_22b_q8p.ckpt", "ltx2.3")] {
      let result = try #require(VideoDefaults.applying(to: start, file: file, family: family))
      #expect(result.video.usesSolAttention == false)
      #expect(result.advanced.teaCache == false)
    }
  }

  @Test func imageFamilyGivesNil() {
    #expect(VideoDefaults.applying(to: GenerationParameters(), file: "flux_2_klein_9b_f16.ckpt", family: "flux2_9b") == nil)
    #expect(VideoDefaults.applying(to: GenerationParameters(), file: "x.ckpt", family: nil) == nil)
  }

  @Test func keepsSeedBatchAndLoRAs() throws {
    var start = GenerationParameters()
    start.seed = 4242
    start.randomSeed = false
    start.batchCount = 3
    start.loras = [LoRASelection(file: "a_lora_f16.ckpt", weight: 0.6)]
    let result = try #require(
      VideoDefaults.applying(to: start, file: "minimax_h3_ref2va_i4x.ckpt", family: "minimax_h3"))
    #expect(result.seed == 4242)
    #expect(result.randomSeed == false)
    #expect(result.batchCount == 3)
    #expect(result.loras == start.loras)
  }
}
