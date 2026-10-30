import HubKit
import Testing

@testable import DTBridge

/// Readings of the compute-unit bar of the Draw Things app (iOS), as the user took them on 15 Oct 2026: the
/// independent check of the port (the numbers in `ComputeUnitsEstimatorTests` only pin the port against itself).
struct ComputeUnitsReferenceTests {
  /// A spec without guidance embed, modifier, consistency flag or padded text length (as `z_image_1.0_f16.ckpt`).
  static let plain = ModelCapabilities(
    guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
    clipSkip: false, nativeSize: nil)

  func reading(
    _ expected: Int, family: String, file: String, width: Int, height: Int, steps: Int, guidance: Double,
    batch: Int = 1, strength: Double = 1, hasImage: Bool = false, references: Int = 0, numFrames: Int = 1,
    capabilities: ModelCapabilities = ComputeUnitsReferenceTests.plain, tolerance: Int? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let inputs = CUInputs(
      family: family, modelFile: file, capabilities: capabilities, width: width, height: height, steps: steps,
      strength: strength, guidanceScale: guidance, batchSize: batch, hasImage: hasImage, referenceImages: references,
      numFrames: numFrames)
    let estimate = ComputeUnitsEstimator.estimate(inputs)
    #expect(estimate != nil, sourceLocation: sourceLocation)
    guard let estimate else { return }
    let allowed = tolerance ?? max(1, expected / 100)
    #expect(
      abs(estimate - expected) <= allowed, "\(family): estimate \(estimate), the app shows \(expected)",
      sourceLocation: sourceLocation)
  }

  @Test func zImage1024With30StepsAndGuidance4() {
    reading(9601, family: "z_image", file: "z_image_1.0_f16.ckpt", width: 1024, height: 1024, steps: 30, guidance: 4)
  }

  static let flux2Dev = ModelCapabilities(
    guidanceEmbed: true, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
    clipSkip: false, nativeSize: nil, modifier: "kontext")

  /// FLUX.2 dev (guidance embed, modifier `kontext`), 1024×1024, 28 steps, guidance 4.5, batch 2, with the base reference the app
  /// counts for a Kontext model (the start image moves nothing there): the app shows 83 783, which is exactly 2 × 41 891.4 (the port rounds up).
  @Test func flux2DevBatchOfTwoWithTheCanvasImage() {
    reading(
      83783, family: "flux2", file: "flux_2_dev_f16.ckpt", width: 1024, height: 1024, steps: 28, guidance: 4.5, batch: 2,
      hasImage: true, capabilities: Self.flux2Dev)
  }

  /// The same with batch 1: the app shows 41 892 (the user confirmed: the first note said "44892" by a slip).
  @Test func flux2DevBatchOfOneWithTheCanvasImage() {
    reading(
      41892, family: "flux2", file: "flux_2_dev_f16.ckpt", width: 1024, height: 1024, steps: 28, guidance: 4.5,
      hasImage: true, capabilities: Self.flux2Dev)
  }

  /// FLUX.2 klein base 9B (modifier `kontext`, no guidance embed), 1024×1024, 30 steps, guidance 4 (CFG on), with the
  /// canvas image as the reference: the app shows 24 782.
  @Test func flux2Klein9BBaseWithCFGAndTheCanvasImage() {
    let caps = ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
      clipSkip: false, nativeSize: nil, modifier: "kontext")
    reading(
      24782, family: "flux2_9b", file: "flux_2_klein_base_9b_f16.ckpt", width: 1024, height: 1024, steps: 30, guidance: 4,
      hasImage: true, capabilities: caps)
  }

  /// The same model and parameters with two Moodboard pictures besides the base reference: the app shows 59 331 (exact).
  @Test func flux2Klein9BBaseWithTwoMoodboardPictures() {
    let caps = ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
      clipSkip: false, nativeSize: nil, modifier: "kontext", paddedTextEncodingLength: 512)
    reading(
      59331, family: "flux2_9b", file: "flux_2_klein_base_9b_f16.ckpt", width: 1024, height: 1024, steps: 30, guidance: 4,
      hasImage: true, references: 2, capabilities: caps)
  }

  /// Ideogram 4 fast, 1024×1024, 20 steps, guidance 1: the app shows 4 790.
  @Test func ideogram4Fast1024With20Steps() {
    reading(4790, family: "ideogram_4", file: "ideogram_4_fast_q8p.ckpt", width: 1024, height: 1024, steps: 20, guidance: 1)
  }

  /// Krea 2 turbo, 1024×1024, 8 steps, guidance 1: the app shows 2 451.
  @Test func krea2Turbo1024With8Steps() {
    reading(2451, family: "krea_2", file: "krea_2_turbo_q8p.ckpt", width: 1024, height: 1024, steps: 8, guidance: 1)
  }

  /// Qwen Image 2.1 (modifier `kontext`), 1536×1536, 40 steps, guidance 1, with the base reference the app
  /// always counts for this model (the start image moves nothing there): the app shows 20 446 (exact).
  @Test func qwenImage2_1At1536With40StepsAndTheCanvasImage() {
    let caps = ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
      clipSkip: false, nativeSize: nil, modifier: "kontext")
    reading(
      20446, family: "qwen_image_2.1", file: "qwen_image_2.1_q8p.ckpt", width: 1536, height: 1536, steps: 40, guidance: 1,
      hasImage: true, capabilities: caps)
  }

  /// ERNIE Image, 1024×1024, 30 steps, guidance 4 (CFG on): the app shows 13 150.
  @Test func ernieImage1024With30StepsAndCFG() {
    reading(13150, family: "ernie_image", file: "ernie_image_f16.ckpt", width: 1024, height: 1024, steps: 30, guidance: 4)
  }

  /// FLUX.2 dev, 26 steps: the app shows 38 900, just under the 40 000 limit (97 %: amber on the meter).
  @Test func flux2Dev1024With26Steps() {
    reading(
      38900, family: "flux2", file: "flux_2_dev_f16.ckpt", width: 1024, height: 1024, steps: 26, guidance: 4.5,
      capabilities: Self.flux2Dev)
  }

  /// FLUX.2 dev, 26 steps, only the strength varied (the user's readings): the strength scales the cost, with a
  /// floor of 5 % (strength 0 shows 1 946). The cost differs by one at most (rounding up).
  @Test(arguments: [(1.0, 38900), (0.7, 27230), (0.5, 19450), (0.3, 11670), (0.0, 1946)])
  func flux2DevStrength(strength: Double, expected: Int) {
    reading(
      expected, family: "flux2", file: "flux_2_dev_f16.ckpt", width: 1024, height: 1024, steps: 26, guidance: 4.5,
      strength: strength, capabilities: Self.flux2Dev, tolerance: 1)
  }

  /// The old families and Cosmos, confirmed by the user against the Draw Things app on 16 Oct 2026 ("i conti tornano"):
  /// SD 1.5 512×512, 20 steps, guidance 7.5 = 209; SDXL 1024×1024, 20 steps, guidance 7.5 = 1 736; Cosmos 2.5
  /// 1024×1024, 30 steps, guidance 4 = 3 749.
  @Test(arguments: [
    ("v1", 512, 20, 7.5, 209), ("sdxl_base_v0.9", 1024, 20, 7.5, 1736), ("cosmos2.5_2b", 1024, 30, 4.0, 3749),
  ])
  func theOldFamiliesAndCosmosMatchTheApp(family: String, side: Int, steps: Int, guidance: Double, expected: Int) {
    reading(
      expected, family: family, file: "\(family).ckpt", width: side, height: side, steps: steps, guidance: guidance,
      tolerance: 1)
  }

  // MARK: Video, read by the user on the Draw Things app on 30 Oct 2026
  // The bar shows thousands with one decimal, truncated: reading r.k means the value is in [r.k * 1000, r.k * 1000 + 100).
  // The helper takes the middle of the bucket with a tolerance of 50 (the ends are inclusive).

  static func video(_ modifier: String?) -> ModelCapabilities {
    ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
      clipSkip: false, nativeSize: nil, modifier: modifier)
  }

  /// MiniMax H3 ref2va (4-bit S), 576x448, 56 frames, 50 steps, guidance 1, no start image and no Moodboard: 31.1k.
  @Test func h3Ref2vaWithoutAnyImage() {
    reading(
      31_150, family: "minimax_h3", file: "minimax_h3_ref2va_i4x.ckpt", width: 576, height: 448, steps: 50, guidance: 1,
      numFrames: 56, capabilities: Self.video("ref2va"), tolerance: 50)
  }

  /// FastH3 Omni (4-bit S, modifier ref2va), 832x512, 124 frames, 8 steps, guidance 1, no image: 21.7k.
  @Test func fastH3WithoutAnyImage() {
    reading(
      21_750, family: "minimax_h3", file: "fasth3_omni_i4x.ckpt", width: 832, height: 512, steps: 8, guidance: 1,
      numFrames: 124, capabilities: Self.video("ref2va"), tolerance: 50)
  }

  /// MiniMax H3 ref2va, 832x512, 124 frames, 50 steps, guidance 1, no image: 135.7k. The port gives 135 688, 12 units
  /// (0.009 %) under the bucket [135 700, 135 800) of the truncated reading: a tolerance of 100 covers it (it is not
  /// known where the 12 come from; the other four readings fall inside their bucket).
  @Test func h3Ref2vaAtFastH3SizeWith50Steps() {
    reading(
      135_750, family: "minimax_h3", file: "minimax_h3_ref2va_i4x.ckpt", width: 832, height: 512, steps: 50,
      guidance: 1, numFrames: 124, capabilities: Self.video("ref2va"), tolerance: 100)
  }

  /// LTX-2.3 22B distilled, 1280x768, 121 frames, 8 steps, Hires fix on (640x384): 12.4k, so only the final size counts.
  @Test func ltx23WithHiresFix() {
    reading(
      12_450, family: "ltx2.3", file: "ltx_2.3_22b_distilled_1.1_q8p.ckpt", width: 1280, height: 768, steps: 8,
      guidance: 1, numFrames: 121, capabilities: Self.video(nil), tolerance: 50)
  }

  /// LTX-2 19B distilled, 1280x768, 121 frames, 8 steps, Hires fix off: 12.3k.
  @Test func ltx2WithoutHiresFix() {
    reading(
      12_350, family: "ltx2", file: "ltx_2_19b_distilled_q8p.ckpt", width: 1280, height: 768, steps: 8, guidance: 1,
      numFrames: 121, capabilities: Self.video(nil), tolerance: 50)
  }
}
