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
    #expect(TUPresetTable.preset(forFamily: "flux2") == nil)
    #expect(TUPresetTable.preset(forFamily: nil) == nil)
    #expect(TUPresetTable.preset(forFamily: "qwen_image_2.1", model: nil) == nil, "without the file it cannot tell Turbo from the other")
  }

  @Test func qwen21TurboHasItsOwnValues() throws {
    let preset = try #require(TUPresetTable.preset(forFamily: "qwen_image_2.1", model: "qwen_image_2.1_turbo_i8x.ckpt"))
    #expect(preset.name == "TUP · Qwen Image 2.1 Turbo")
    #expect(preset.steps == 8 && preset.guidanceScale == 1 && preset.sampler == 16 && preset.shift == 6.5 && preset.strength == 1)
    #expect(preset.resolutionDependentShift == false)
    #expect(preset.loraFile == "q21_detail_fix_2.0_lora_f16.ckpt" && preset.defaultLoRAWeight == 2.5)
    let fields = preset.fields(prompt: "p")
    #expect(fields["steps"] as? Int == 8 && fields["shift"] as? Double == 6.5 && fields["resolutionDependentShift"] as? Bool == false)
  }

  @Test func qwen21HasItsOwnValuesToo() throws {
    let preset = try #require(TUPresetTable.preset(forFamily: "qwen_image_2.1", model: "qwen_image_2.1_i8x.ckpt"))
    #expect(preset.name == "TUP · Qwen Image 2.1")
    #expect(preset.steps == 33 && preset.guidanceScale == 1 && preset.sampler == 16 && preset.shift == 1 && preset.strength == 1)
    #expect(preset.resolutionDependentShift == true, "this one works out its shift from the size")
    #expect(preset.loraFile == "q21_detail_fix_2.0_lora_f16.ckpt" && preset.defaultLoRAWeight == 2.5)
    #expect(preset.fields(prompt: "p")["resolutionDependentShift"] as? Bool == true)
  }

  @Test func fluxHasItsFixedPromptWhateverTheLoRAsTriggerIs() throws {
    // The trigger of the LoRA on the server has "face", "expression", "figure", "pose": on a tile with no face the model adds one.
    let flux = try #require(TUPresetTable.preset(forFamily: "flux2_9b"))
    let expected = "make this photo high-quality. preserve details. preserve overall composition of this photo. Preserve colors and lights."
    #expect(TUPresetTable.fluxPrompt == expected)
    #expect(flux.prompt(trigger: "face expression figure pose") == expected)
    #expect(flux.prompt(trigger: "") == expected)
    #expect(!expected.lowercased().contains("face") && !expected.lowercased().contains("expression"))
  }

  @Test func bothFamiliesUseTheirFixedPrompt() throws {
    let qwen = try #require(TUPresetTable.preset(forFamily: "qwen_image_2.1", model: "qwen_image_2.1_turbo_i8x.ckpt"))
    #expect(qwen.prompt(trigger: "ANYTHING").hasPrefix("Upscale this image to a substantially higher resolution"))
    #expect(qwen.prompt(trigger: "ANYTHING").hasSuffix("a cleaner, richer, higher-resolution version of the same image."))
    #expect(qwen.prompt(trigger: "ANYTHING") == qwen.prompt(trigger: ""), "no trigger word in it")
    let flux = try #require(TUPresetTable.preset(forFamily: "flux2_9b"))
    #expect(flux.prompt(trigger: "T") == TUPresetTable.fluxPrompt, "no trigger word in it either")
    // The same sentence for both Qwen models.
    let normal = try #require(TUPresetTable.preset(forFamily: "qwen_image_2.1", model: "qwen_image_2.1_i8x.ckpt"))
    #expect(normal.prompt(trigger: "") == qwen.prompt(trigger: ""))
  }

  @Test func theMaskSettingsAreThe30And30OfTheSpec() {
    #expect(TUPresetTable.maskBlur == 30 && TUPresetTable.maskOutset == 30)
  }

  @Test func theFixedSentenceFollowsTheTriggerWord() {
    #expect(TUPrompt.text(trigger: "TRIG") == "TRIG ALSO PRESERVE COLORS AND LUMINOSITY")
    #expect(TUPrompt.text(trigger: "") == "ALSO PRESERVE COLORS AND LUMINOSITY")
    #expect(TUPrompt.text(trigger: "  TRIG  ") == "TRIG ALSO PRESERVE COLORS AND LUMINOSITY")
  }

  @Test func theFieldsPinEveryValueOfThePresetSoTheTabsDoNotLeakIn() throws {
    let preset = try #require(TUPresetTable.preset(forFamily: "flux2_9b"))
    let fields = preset.fields(prompt: "p")
    #expect(fields["resolutionDependentShift"] as? Bool == false, "shift stays 3: it is not computed from the size")
    #expect(fields["cfgZeroStar"] as? Bool == false)
    #expect(fields["cfgZeroInitSteps"] as? Int == 0)
    #expect(fields["shift"] as? Double == 3 && fields["steps"] as? Int == 4 && fields["sampler"] as? Int == 16)
    #expect(fields["guidanceScale"] as? Double == 1)
  }
}
