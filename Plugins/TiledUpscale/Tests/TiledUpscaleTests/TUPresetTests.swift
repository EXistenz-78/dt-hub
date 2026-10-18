import Testing

@testable import TiledUpscale

struct TUPresetTests {
  @Test func fluxKlein9BHasThePresetValues() throws {
    let preset = try #require(TUPresetTable.preset(forFamily: "flux2_9b"))
    #expect(preset.name == "TUP · FLUX.2 klein 9B")
    #expect(preset.steps == 4)
    #expect(preset.guidanceScale == 1)
    #expect(preset.sampler == 16)
    #expect(preset.shift == 3)
    #expect(preset.strength == 1)
    #expect(preset.loraFile == "f2_ultra_real_v5_pro_lora_f16.ckpt")
    #expect(preset.defaultLoRAWeight == 1)
  }

  @Test func unknownFamiliesHaveNoPreset() {
    #expect(TUPresetTable.preset(forFamily: "qwen_image_2.1") == nil)
    #expect(TUPresetTable.preset(forFamily: nil) == nil)
  }

  @Test func theMaskSettingsAreThe30And30OfTheSpec() {
    #expect(TUPresetTable.maskBlur == 30 && TUPresetTable.maskOutset == 30)
  }

  @Test func theFixedSentenceFollowsTheTriggerWord() {
    #expect(TUPrompt.text(trigger: "TRIG") == "TRIG ALSO PRESERVE COLORS AND LUMINOSITY")
    #expect(TUPrompt.text(trigger: "") == "ALSO PRESERVE COLORS AND LUMINOSITY")
    #expect(TUPrompt.text(trigger: "  TRIG  ") == "TRIG ALSO PRESERVE COLORS AND LUMINOSITY")
  }
}
