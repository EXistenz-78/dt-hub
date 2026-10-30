import HubKit
import Testing

@testable import DTBridge

struct ComputeUnitsEstimatorTests {
  /// A model without guidance embed, consistency or modifier: the guidance scale decides about CFG.
  static let plain = ModelCapabilities(
    guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
    clipSkip: false, nativeSize: nil)

  func inputs(
    _ family: String, width: Int = 1024, height: Int = 1024, steps: Int = 20, strength: Double = 1,
    guidance: Double = 1, batch: Int = 1, hasImage: Bool = false, references: Int = 0,
    capabilities: ModelCapabilities = ComputeUnitsEstimatorTests.plain
  ) -> CUInputs {
    CUInputs(
      family: family, modelFile: "test.ckpt", capabilities: capabilities, width: width, height: height, steps: steps,
      strength: strength, guidanceScale: guidance, batchSize: batch, hasImage: hasImage, referenceImages: references)
  }

  func estimate(_ i: CUInputs) -> Int { ComputeUnitsEstimator.estimate(i) ?? -1 }

  @Test func zImageGrowsWithTheSteps() {
    let few = estimate(inputs("z_image", steps: 8))
    let many = estimate(inputs("z_image", steps: 16))
    #expect(few > 0)
    #expect(abs(Double(many) / Double(few) - 2) < 0.1)
  }

  @Test func theBatchMultipliesTheEstimate() {
    let one = estimate(inputs("z_image", batch: 1))
    let two = estimate(inputs("z_image", batch: 2))
    #expect(abs(Double(two) / Double(one) - 2) < 0.1)
  }

  @Test func strengthScalesTheEstimateAndIsFlooredAtFivePercent() {
    #expect(estimate(inputs("z_image", strength: 0.5)) < estimate(inputs("z_image", strength: 1)))
    #expect(estimate(inputs("z_image", strength: 0)) == estimate(inputs("z_image", strength: 0.05)))
  }

  @Test func cfgDoublesTheWork() {
    let without = estimate(inputs("z_image", guidance: 1))
    let with = estimate(inputs("z_image", guidance: 4))
    #expect(abs(Double(with) / Double(without) - 2) < 0.1)
  }

  @Test func flux3KleinAndMossHaveAnEstimate() {
    for family in ["flux3_5b", "moss_image"] {
      let few = estimate(inputs(family, steps: 8))
      let many = estimate(inputs(family, steps: 16))
      #expect(few > 0, "\(family)")
      #expect(abs(Double(many) / Double(few) - 2) < 0.1, "\(family)")
      #expect(estimate(inputs(family, width: 2048, height: 2048)) > few, "\(family)")
    }
  }

  @Test func mossCfgDoublesTheWork() {
    let without = estimate(inputs("moss_image", guidance: 1))
    let with = estimate(inputs("moss_image", guidance: 4))
    #expect(abs(Double(with) / Double(without) - 2) < 0.15)
  }

  @Test func flux3ReferencesAddWork() {
    let kontext = ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
      clipSkip: false, nativeSize: nil, modifier: "kontext")
    let none = estimate(inputs("flux3_5b", capabilities: kontext))
    let two = estimate(inputs("flux3_5b", references: 2, capabilities: kontext))
    #expect(two > none)
  }

  @Test func anUncoveredFamilyHasNoEstimate() {
    #expect(ComputeUnitsEstimator.estimate(inputs("wurstchen_v3.0_stage_c")) == nil)
    #expect(ComputeUnitsEstimator.estimate(inputs("kandinsky2.1")) == nil)
    #expect(ComputeUnitsEstimator.estimate(inputs("wan_v2.1_14b")) == nil)
  }

  @Test func nonsenseInputsHaveNoEstimateAndDoNotTrap() {
    #expect(ComputeUnitsEstimator.estimate(inputs("z_image", steps: 0)) == nil)
    #expect(ComputeUnitsEstimator.estimate(inputs("z_image", width: 0)) == nil)
    #expect(ComputeUnitsEstimator.estimate(inputs("z_image", height: 0)) == nil)
    #expect(ComputeUnitsEstimator.estimate(inputs("z_image", batch: 0)) == nil)
  }

  @Test func hugeInputsAreCappedWithoutTrapping() throws {
    let huge = try #require(ComputeUnitsEstimator.estimate(inputs("z_image", width: 8192, height: 8192, batch: 64)))
    #expect(huge > 0 && huge <= ComputeUnitsEstimator.ceiling)
  }

  @Test(arguments: ["qwen_image", "qwen_image_2.1", "ernie_image", "ideogram_4", "seedvr2_3b", "seedvr2_7b"])
  func theFamiliesOfThisGroupHaveAnEstimate(family: String) {
    #expect(estimate(inputs(family, steps: 20, guidance: 4)) > 0)
  }

  @Test func qwenImage2_1SharesItsPrefixWorkAcrossTheBatch() {
    let single = estimate(inputs("qwen_image_2.1", batch: 1))
    let batch = estimate(inputs("qwen_image_2.1", batch: 2))
    #expect(batch > single)
    #expect(batch < 2 * single)
  }

  @Test(arguments: ["flux1", "flux2", "flux2_9b", "flux2_4b", "krea_2"])
  func theFluxAndKreaFamiliesHaveAnEstimate(family: String) {
    #expect(estimate(inputs(family, steps: 20, guidance: 4)) > 0)
  }

  func edit(_ modifier: String) -> ModelCapabilities {
    ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
      clipSkip: false, nativeSize: nil, modifier: modifier)
  }

  @Test func referenceImagesRaiseTheEstimateOfAnEditModel() {
    let none = estimate(inputs("flux2_9b", hasImage: true, references: 0, capabilities: edit("kontext")))
    let two = estimate(inputs("flux2_9b", hasImage: true, references: 2, capabilities: edit("kontext")))
    #expect(two > none)
  }

  @Test func theKVCacheMovesReferenceWorkAwayFromEveryStep() {
    let plain = estimate(inputs("flux2_9b", hasImage: true, references: 1, capabilities: edit("kontext")))
    let cached = estimate(inputs("flux2_9b", hasImage: true, references: 1, capabilities: edit("kontext_kv")))
    #expect(cached != plain)
    #expect(cached < plain)
  }

  @Test func aReferenceImageMeansNothingToAModelWithoutAModifier() {
    let none = estimate(inputs("flux2_9b", references: 0))
    let some = estimate(inputs("flux2_9b", references: 3))
    #expect(none > 0)
    #expect(none == some)
  }

  @Test(arguments: ["sd3", "sd3_large", "pixart", "auraflow", "hidream_i1", "hidream_o1"])
  func theLastGroupOfFamiliesHasAnEstimate(family: String) {
    #expect(estimate(inputs(family, steps: 20, guidance: 4)) > 0)
  }

  @Test func sd3DualAttentionLayersRaiseTheEstimate() {
    func caps(_ layers: [Int]) -> ModelCapabilities {
      ModelCapabilities(
        guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
        clipSkip: false, nativeSize: nil, dualAttentionLayers: layers)
    }
    let none = estimate(inputs("sd3", capabilities: caps([])))
    let some = estimate(inputs("sd3", capabilities: caps([0, 1, 2])))
    #expect(none > 0)
    #expect(some > none)
  }

  @Test func manyReferencePicturesOnAHugeCanvasAreCappedWithoutTrapping() throws {
    // Attention grows with the square of the sequence, and the pictures add to it: this overflowed Int.
    let qwenEdit = try #require(
      ComputeUnitsEstimator.estimate(
        inputs(
          "qwen_image", width: 8192, height: 8192, guidance: 4, batch: 4, hasImage: true, references: 5,
          capabilities: edit("qwenimage_edit_plus"))))
    #expect(qwenEdit == ComputeUnitsEstimator.ceiling)
    let kontext = try #require(
      ComputeUnitsEstimator.estimate(
        inputs(
          "flux2", width: 8192, height: 8192, guidance: 4, batch: 4, hasImage: true, references: 11,
          capabilities: edit("kontext"))))
    #expect(kontext == ComputeUnitsEstimator.ceiling)
  }

  /// A regression pin of the port as written on 15 Oct 2026 (1024×1024, 20 steps, guidance 4): a change to a count
  /// shows here. The independent check is the user's readings of the Draw Things CU bar.
  @Test(arguments: [
    ("z_image", 6402), ("flux1", 7678), ("flux2_9b", 7775), ("krea_2", 12244), ("qwen_image_2.1", 6963),
    ("ideogram_4", 9580),
  ])
  func theEstimatesAreStable(family: String, expected: Int) {
    let value = estimate(inputs(family, steps: 20, guidance: 4))
    #expect(value == expected, "\(family) -> \(value)")
  }

  @Test func theStartImageDoesNotChangeTheEstimateOfAKontextModel() {
    // The Draw Things app counts one base reference for these models whether or not there is a start image
    // (the user's readings of 15 Oct 2026: the start image moves nothing, only the Moodboard does).
    let caps = edit("kontext")
    for family in ["flux2_9b", "flux2", "qwen_image_2.1"] {
      let without = estimate(inputs(family, hasImage: false, capabilities: caps))
      let with = estimate(inputs(family, hasImage: true, capabilities: caps))
      #expect(without > 0)
      #expect(without == with, "\(family)")
    }
  }

  @Test func theMoodboardAddsToTheBaseReference() {
    let caps = edit("kontext")
    let none = estimate(inputs("flux2_9b", references: 0, capabilities: caps))
    let two = estimate(inputs("flux2_9b", references: 2, capabilities: caps))
    #expect(two > none)
  }

  @Test(arguments: ["v1", "v2", "sdxl_base_v0.9", "sdxl_refiner_v0.9", "ssd_1b", "cosmos2.5_2b"])
  func theOldImageFamiliesAndCosmosHaveAnEstimate(family: String) {
    #expect(estimate(inputs(family, width: 512, height: 512, steps: 20, guidance: 7.5)) > 0)
  }

  @Test func sdxlGrowsWithTheSizeTheStepsAndTheBatch() {
    let base = estimate(inputs("sdxl_base_v0.9", width: 1024, height: 1024, steps: 20, guidance: 7.5))
    #expect(estimate(inputs("sdxl_base_v0.9", width: 1024, height: 1024, steps: 40, guidance: 7.5)) > base)
    #expect(estimate(inputs("sdxl_base_v0.9", width: 1536, height: 1536, steps: 20, guidance: 7.5)) > base)
    let two = estimate(inputs("sdxl_base_v0.9", width: 1024, height: 1024, steps: 20, guidance: 7.5, batch: 2))
    #expect(abs(Double(two) / Double(base) - 2) < 0.1)
  }

  @Test func theOldFamiliesCarryTheUsageBias() {
    // SD 1.x/2.x and SDXL count 2.5 times their instruction cost; Cosmos and the modern families count 1.
    #expect(ComputeUnitsEstimator.usageBias(.sd15) == 2.5 && ComputeUnitsEstimator.usageBias(.sdxlBase) == 2.5)
    #expect(ComputeUnitsEstimator.usageBias(.cosmos2_5_2b) == 1.0 && ComputeUnitsEstimator.usageBias(.zImage) == 1.0)
  }

  // MARK: Video (MiniMax H3, LTX-2.3)
  // These pin the port against itself (the formulas as written in draw-things-community at bd372b2): they are not
  // Draw Things' bar. The independent check is the user comparing with the CU bar of the Draw Things app.

  func video(
    _ family: String, width: Int, height: Int, frames: Int, steps: Int, guidance: Double = 1, hasImage: Bool = false,
    references: Int = 0, modifier: String? = nil
  ) -> CUInputs {
    let caps = ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
      clipSkip: false, nativeSize: nil, modifier: modifier)
    return CUInputs(
      family: family, modelFile: "video.ckpt", capabilities: caps, width: width, height: height, steps: steps,
      guidanceScale: guidance, hasImage: hasImage, referenceImages: references, numFrames: frames)
  }

  @Test func h3LatentFramesFollowTheOriginalAndRoundTrip() {
    let expected = [(5, 2), (22, 7), (56, 17), (124, 37)]
    for (frames, latent) in expected {
      #expect(ComputeUnitsEstimator.latentFrames(family: .minimaxH3, numFrames: frames) == latent, "\(frames)")
      #expect(ComputeUnitsEstimator.h3VideoFrames(latentFrames: latent) == frames, "\(latent)")
    }
    #expect(ComputeUnitsEstimator.latentFrames(family: .minimaxH3, numFrames: 1) == 1)
    #expect(ComputeUnitsEstimator.h3VideoFrames(latentFrames: 1) == 1)
  }

  @Test func ltxLatentFramesAreOneEighthPlusOne() {
    #expect(ComputeUnitsEstimator.latentFrames(family: .ltx2_3, numFrames: 25) == 4)
    #expect(ComputeUnitsEstimator.latentFrames(family: .ltx2_3, numFrames: 121) == 16)
    #expect(ComputeUnitsEstimator.latentFrames(family: .ltx2, numFrames: 1) == 1)
    #expect(ComputeUnitsEstimator.latentFrames(family: .ltx2_3, numFrames: 0) == 1)
  }

  @Test func theStartSizeOfVideoIsRawTimesFourForH3AndTwoForLTX() {
    #expect(ComputeUnitsEstimator.startFactor(.minimaxH3) == 4)
    #expect(ComputeUnitsEstimator.startFactor(.ltx2) == 2 && ComputeUnitsEstimator.startFactor(.ltx2_3) == 2)
  }

  @Test func ltxFixedCountMatchesTheHandComputedFormula() {
    // channels (32, 32), one timestep, no KV, no context projection, no text AdaLN: per stream the AdaLN blocks
    // with 6, 4 and 1 projections cost t*256*c + (1+n)*t*c*c each = 15360 + 13312 + 10240 = 38912; two streams.
    #expect(
      LTX2FixedInstructionCount(
        time: 1, textLength: 1, audioFrames: 1, timesteps: 1, channels: (32, 32), layers: 1,
        contextProjection: false, textCrossAttentionAdaLN: false, KV: false) == 2 * 38912)
  }

  @Test func h3FixedCountMatchesTheHandComputedFormula() {
    // hidden 8, one layer, one timestep, text (0, 2), no reference: rows = 2.
    // 4096 + 43008 + 20 * 43008 + 81920 + 0 + 2 * 517216 + 2 * 688128 = 3_399_872
    #expect(
      MiniMaxH3FixedInstructionCount(timesteps: 1, hiddenSize: 8, layers: 1, textLength: (0, 2)) == 3_399_872)
  }

  @Test func h3GrowsWithTheFramesAndTheSteps() {
    let short = estimate(video("minimax_h3", width: 576, height: 448, frames: 22, steps: 50))
    let mid = estimate(video("minimax_h3", width: 576, height: 448, frames: 56, steps: 50))
    let long = estimate(video("minimax_h3", width: 576, height: 448, frames: 124, steps: 50))
    #expect(short > 0 && short < mid && mid < long)
    #expect(estimate(video("minimax_h3", width: 576, height: 448, frames: 56, steps: 8)) < mid)
  }

  @Test(arguments: ["ltx2", "ltx2.3"])
  func ltxGrowsWithTheFramesAndTheSteps(family: String) {
    let short = estimate(video(family, width: 768, height: 448, frames: 25, steps: 8))
    let mid = estimate(video(family, width: 768, height: 448, frames: 81, steps: 8))
    let long = estimate(video(family, width: 768, height: 448, frames: 121, steps: 8))
    #expect(short > 0 && short < mid && mid < long)
    #expect(estimate(video(family, width: 768, height: 448, frames: 25, steps: 16)) > short)
  }

  @Test(arguments: ["wan_v2.2_5b", "wan_v2.1_14b", "hunyuan_video", "svd_i2v"])
  func aVideoFamilyThePortDoesNotCoverHasNoEstimate(family: String) {
    #expect(ComputeUnitsEstimator.estimate(video(family, width: 768, height: 448, frames: 25, steps: 8)) == nil)
  }

  @Test func theBatchSizeDoesNotChangeAVideoEstimate() {
    // In the original the batch of a video model is the CFG channels alone.
    var one = video("ltx2.3", width: 768, height: 448, frames: 25, steps: 8)
    let base = estimate(one)
    one.batchSize = 3
    #expect(estimate(one) == base)
  }

  @Test func cfgDoublesTheWorkOfAVideoModel() {
    let off = estimate(video("ltx2.3", width: 768, height: 448, frames: 25, steps: 8, guidance: 1))
    let on = estimate(video("ltx2.3", width: 768, height: 448, frames: 25, steps: 8, guidance: 3))
    #expect(on > off && Double(on) / Double(off) < 2.1)
  }

  @Test func aRef2vaModelAlwaysCountsTheBaseReferenceAndTheMoodboardAddsToIt() {
    func h3(_ hasImage: Bool, _ refs: Int, _ modifier: String = "ref2va") -> Int {
      estimate(
        video(
          "minimax_h3", width: 576, height: 448, frames: 56, steps: 50, hasImage: hasImage, references: refs,
          modifier: modifier))
    }
    // The Draw Things bar counts the base reference with or without a start image (readings of 30 Oct 2026).
    #expect(h3(false, 0) == h3(true, 0))
    #expect(h3(false, 0) > h3(false, 0, "none"))
    #expect(h3(false, 1) > h3(false, 0) && h3(false, 2) > h3(false, 1))
    // fl2va (unverified against the bar): the base reference plus at most one more.
    #expect(h3(false, 5, "fl2va") == h3(false, 1, "fl2va"))
    #expect(h3(false, 1, "fl2va") > h3(false, 0, "fl2va"))
  }

  /// A regression pin of the port as written on 30 Oct 2026 (the first-pass size is not used: the original counts
  /// the final size once; H3 counts the base reference of ref2va without an image, the real model is ref2va). Not Draw Things' bar.
  @Test(arguments: [
    ("minimax_h3", 576, 448, 56, 50, 31_126), ("minimax_h3", 832, 512, 124, 8, 21_712),
    ("ltx2.3", 768, 448, 25, 8, 857), ("ltx2.3", 1280, 768, 121, 8, 12_455), ("ltx2", 768, 448, 25, 8, 782),
  ])
  func theVideoEstimatesAreStable(family: String, width: Int, height: Int, frames: Int, steps: Int, expected: Int) {
    let modifier = family == "minimax_h3" ? "ref2va" : nil  // every H3 model is ref2va or fl2va
    let value = estimate(
      video(family, width: width, height: height, frames: frames, steps: steps, modifier: modifier))
    #expect(value == expected, "\(family) -> \(value)")
  }

  @Test func theLargestDefaultVideoRequestsAreSaneAndFarBelowTheCeiling() throws {
    let ltx = try #require(
      ComputeUnitsEstimator.estimate(video("ltx2.3", width: 1280, height: 768, frames: 121, steps: 8)))
    let h3 = try #require(
      ComputeUnitsEstimator.estimate(video("minimax_h3", width: 832, height: 512, frames: 124, steps: 8)))
    for value in [ltx, h3] { #expect(value > 0 && value < 1_000_000, "\(value)") }
  }

  @Test func absurdVideoRequestsAreCappedWithoutTrapping() throws {
    let ltx = try #require(
      ComputeUnitsEstimator.estimate(video("ltx2.3", width: 8192, height: 8192, frames: 100_000, steps: 8)))
    #expect(ltx == ComputeUnitsEstimator.ceiling)
    let h3 = try #require(
      ComputeUnitsEstimator.estimate(
        video("minimax_h3", width: 4096, height: 4096, frames: 1_000_000, steps: 50, hasImage: true, references: 20, modifier: "ref2va")))
    #expect(h3 == ComputeUnitsEstimator.ceiling)
    // Absurd frame counts at the smallest size (audio and text rows count too) hit the ceiling and do not trap.
    for frames in [1_000_000, 10_000_000, Int.max] {
      #expect(
        ComputeUnitsEstimator.estimate(video("minimax_h3", width: 64, height: 64, frames: frames, steps: 50, guidance: 3))
          == ComputeUnitsEstimator.ceiling, "h3 \(frames)")
    }
    for frames in [5_000_000, Int.max] {
      #expect(
        ComputeUnitsEstimator.estimate(video("ltx2.3", width: 64, height: 64, frames: frames, steps: 8, guidance: 3))
          == ComputeUnitsEstimator.ceiling, "ltx \(frames)")
    }
    // Nonsense frame counts do not trap.
    #expect(ComputeUnitsEstimator.estimate(video("minimax_h3", width: 576, height: 448, frames: -5, steps: 8)) != nil)
    #expect(ComputeUnitsEstimator.estimate(video("ltx2.3", width: 576, height: 448, frames: 0, steps: 8)) != nil)
  }
}
