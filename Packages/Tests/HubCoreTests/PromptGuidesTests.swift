import Testing

@testable import HubCore

struct PromptGuidesTests {
  @Test func hasTheThirteenFamilies() {
    #expect(
      Set(PromptGuides.all.keys)
        == [
          "flux1", "flux2", "flux2_9b", "flux2_4b", "krea_2", "qwen_image", "qwen_image_2.1",
          "z_image", "sdxl_base_v0.9", "v1", "ernie_image", "hidream_i1", "cosmos2.5_2b",
        ])
  }

  @Test func negativeFlagMatchesThePluginData() {
    let withNegative: Set<String> = [
      "krea_2", "qwen_image", "ernie_image", "cosmos2.5_2b", "sdxl_base_v0.9", "v1",
    ]
    for (key, guide) in PromptGuides.all {
      #expect(guide.usesNegative == withNegative.contains(key), "\(key)")
    }
    #expect(PromptGuides.all.values.filter(\.usesNegative).count == 6)
  }

  @Test func notesAreClean() {
    for (key, guide) in PromptGuides.all {
      #expect(!guide.notes.isEmpty, "\(key)")
      #expect(guide.notes.hasPrefix("- "), "\(key)")
      #expect(!guide.notes.contains("Model notes:"), "\(key)")
      #expect(!guide.notes.contains("Provisional master prompt"), "\(key)")
      #expect(!guide.notes.contains("Tag mode is ON"), "\(key)")
    }
  }

  @Test func labelsAreReadable() {
    #expect(PromptGuides.all["flux2_9b"]?.label == "FLUX.2 [klein] 9B")
    #expect(PromptGuides.all["v1"]?.label == "Stable Diffusion 1.5")
  }

  @Test func unknownOrMissingFamilyHasNoGuide() {
    #expect(PromptGuides.guide(for: nil) == nil)
    #expect(PromptGuides.guide(for: "mystery_model") == nil)
    #expect(PromptGuides.guide(for: "flux1")?.label == "FLUX.1")
  }
}
