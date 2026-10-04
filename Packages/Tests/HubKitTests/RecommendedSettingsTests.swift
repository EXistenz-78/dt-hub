import Foundation
import Testing

@testable import HubKit

struct RecommendedSettingsTests {
  let table = RecommendedSettings(
    data: Data(
      """
      {"models":{
        "flux_2_klein_9b":{"steps":4,"guidanceScale":1,"sampler":16,"shift":3,"resolutionDependentShift":false},
        "qwen_image_2512":{"steps":30,"guidanceScale":4,"sampler":17,"shift":2},
        "z_image_1.0":{"steps":30,"guidanceScale":4,"sampler":17,"resolutionDependentShift":true},
        "bad_steps":{"steps":"x","guidanceScale":1,"sampler":1},
        "bad_sampler":{"steps":4,"guidanceScale":1,"sampler":999},
        "no_guidance":{"steps":4,"sampler":1}},
       "families":{"v1":{"steps":16,"guidanceScale":5,"sampler":12,"shift":1,"resolutionDependentShift":false}}}
      """.utf8))

  @Test func theKeyDropsTheQuantizationAndTheExtension() {
    #expect(RecommendedSettings.key(forFile: "flux_2_klein_9b_f16.ckpt") == "flux_2_klein_9b")
    #expect(RecommendedSettings.key(forFile: "flux_2_klein_9b_q6p.ckpt") == "flux_2_klein_9b")
    #expect(RecommendedSettings.key(forFile: "wan_v2.2_a14b_hne_t2v_q6p_svd.ckpt") == "wan_v2.2_a14b_hne_t2v")
    #expect(RecommendedSettings.key(forFile: "juggernaut_reborn_q6p_q8p.ckpt") == "juggernaut_reborn")
    #expect(RecommendedSettings.key(forFile: "plain") == "plain")
  }

  @Test func aModelIsFoundByItsFileWhateverItsQuantization() {
    #expect(table.values(forFile: "flux_2_klein_9b_f16.ckpt", family: nil)?.steps == 4)
    #expect(table.values(forFile: "flux_2_klein_9b_i8x.ckpt", family: "other")?.sampler == .ddimTrailing)
  }

  @Test func aModelNotInTheTableFallsBackOnItsFamilyAndOtherwiseHasNothing() {
    #expect(table.values(forFile: "juggernaut_reborn_q6p_q8p.ckpt", family: "v1")?.steps == 16)
    #expect(table.values(forFile: "juggernaut_reborn_q6p_q8p.ckpt", family: "unknown") == nil)
    #expect(table.values(forFile: "juggernaut_reborn_q6p_q8p.ckpt", family: nil) == nil)
  }

  @Test func damagedEntriesAreLeftOutAndTheRestIsKept() {
    #expect(table.values(forFile: "bad_steps.ckpt", family: nil) == nil)
    #expect(table.values(forFile: "bad_sampler.ckpt", family: nil) == nil)
    #expect(table.values(forFile: "no_guidance.ckpt", family: nil) == nil)
    #expect(table.values(forFile: "qwen_image_2512_q8p.ckpt", family: nil)?.shift == 2)
    #expect(RecommendedSettings(data: Data("garbage".utf8)) == .empty)
    #expect(RecommendedSettings(data: Data("[1]".utf8)) == .empty)
  }

  @Test func applyingChangesOnlyStepsGuidanceSamplerAndShift() {
    var tab = GenerationParameters(width: 768, height: 1280, steps: 30, guidanceScale: 4, seed: 7, randomSeed: false, batchCount: 3)
    tab.loras = [LoRASelection(file: "x.ckpt")]
    tab.advanced.hiresFix = true
    tab.shift = 9
    let values = table.values(forFile: "flux_2_klein_9b_f16.ckpt", family: nil)!
    let result = tab.applying(values)
    #expect(result.steps == 4 && result.guidanceScale == 1 && result.sampler == .ddimTrailing)
    #expect(result.shift == 3 && result.resolutionDependentShift == false)
    var expected = tab
    expected.steps = 4
    expected.guidanceScale = 1
    expected.sampler = .ddimTrailing
    expected.shift = 3
    expected.resolutionDependentShift = false
    #expect(result == expected)
  }

  @Test func aListWithoutAShiftLeavesTheShiftAndTurnsTheSwitchOn() {
    var tab = GenerationParameters()
    tab.shift = 9
    tab.resolutionDependentShift = false
    let result = tab.applying(table.values(forFile: "z_image_1.0_q8p.ckpt", family: nil)!)
    #expect(result.shift == 9 && result.resolutionDependentShift)
    // A list that gives a shift but not the switch leaves the switch.
    var on = GenerationParameters()
    on.resolutionDependentShift = true
    let other = on.applying(table.values(forFile: "qwen_image_2512_q8p.ckpt", family: nil)!)
    #expect(other.shift == 2 && other.resolutionDependentShift)
  }

  @Test func appliedValuesAreLimitedLikeTheCardsLimitThem() {
    let wild = RecommendedValues(steps: 9999, guidanceScale: -3, sampler: .uniPC, shift: 99)
    let result = GenerationParameters().applying(wild)
    #expect(result.steps == GenerationParameters.stepsRange.upperBound)
    #expect(result.guidanceScale == 0 && result.shift == GenerationParameters.shiftRange.upperBound)
  }

  /// The file the app ships (made by the script from Draw Things' list): readable, with the models the app is
  /// used with and the families it falls back on.
  @Test func theShippedTableIsReadableAndKnowsTheCommonModels() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/RecommendedSettings.json"))
    let shipped = RecommendedSettings(data: data)
    #expect(shipped.values(forFile: "flux_2_klein_9b_f16.ckpt", family: nil)?.steps == 4)
    #expect(shipped.values(forFile: "z_image_turbo_1.0_f16.ckpt", family: nil)?.steps == 8)
    #expect(shipped.values(forFile: "qwen_image_2.1_q8p.ckpt", family: nil)?.steps == 40)
    #expect(shipped.values(forFile: "juggernaut_reborn_q6p_q8p.ckpt", family: "v1")?.guidanceScale == 5)
    #expect(shipped.values(forFile: "some_sdxl_finetune.ckpt", family: "sdxl_base_v0.9") != nil)
  }
}
