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
    batch: Int = 1, strength: Double = 1, hasImage: Bool = false, references: Int = 0,
    capabilities: ModelCapabilities = ComputeUnitsReferenceTests.plain, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let inputs = CUInputs(
      family: family, modelFile: file, capabilities: capabilities, width: width, height: height, steps: steps,
      strength: strength, guidanceScale: guidance, batchSize: batch, hasImage: hasImage, referenceImages: references)
    let estimate = ComputeUnitsEstimator.estimate(inputs)
    #expect(estimate != nil, sourceLocation: sourceLocation)
    guard let estimate else { return }
    let tolerance = max(1, expected / 100)
    #expect(
      abs(estimate - expected) <= tolerance, "\(family): estimate \(estimate), the app shows \(expected)",
      sourceLocation: sourceLocation)
  }

  @Test func zImage1024With30StepsAndGuidance4() {
    reading(9601, family: "z_image", file: "z_image_1.0_f16.ckpt", width: 1024, height: 1024, steps: 30, guidance: 4)
  }

  /// FLUX.2 dev (guidance embed, modifier `kontext`), 1024×1024, 28 steps: the app shows 44 892. The port gives 20 375
  /// without an image, 41 892 with one reference picture the size of the canvas (3 000 less, exactly) and 40 749 with
  /// CFG. OPEN: the reading may have been taken with an image on the canvas; asked of the user on 15 Oct 2026.
  @Test func flux2Dev1024With28StepsAndGuidance4_5() {
    let caps = ModelCapabilities(
      guidanceEmbed: true, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
      clipSkip: false, nativeSize: nil, modifier: "kontext")
    withKnownIssue("the 44 892 reading is not yet explained (image on the canvas? see the comment)") {
      reading(
        44892, family: "flux2", file: "flux_2_dev_f16.ckpt", width: 1024, height: 1024, steps: 28, guidance: 4.5,
        capabilities: caps)
    }
  }
}
