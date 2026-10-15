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

  @Test func anUncoveredFamilyHasNoEstimate() {
    #expect(ComputeUnitsEstimator.estimate(inputs("sdxl_base_v0.9")) == nil)
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
}
