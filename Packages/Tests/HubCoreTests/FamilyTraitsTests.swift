import HubKit
import Testing

@testable import HubCore

struct FamilyTraitsTests {
  @Test(arguments: ["flux2_9b", "flux1", "qwen_image", "qwen_image_2.1", "z_image", "krea_2", "ideogram_4", "ernie_image", "sd3"])
  func flowMatchingFamiliesUseShift(family: String) {
    #expect(FamilyTraits.of(family).usesShift)
  }

  @Test(arguments: ["v1", "v2", "sdxl_base_v0.9", "ssd_1b", "kandinsky2.1", "wurstchen_v3.0_stage_c"])
  func otherDiffusionFamiliesDoNot(family: String) {
    #expect(!FamilyTraits.of(family).usesShift)
  }

  @Test func upscalersTakeNoNegativePrompt() {
    #expect(!FamilyTraits.of("seedvr2_7b").usesNegativePrompt)
    #expect(FamilyTraits.of("sdxl_base_v0.9").usesNegativePrompt)
    #expect(FamilyTraits.of("flux2_9b").usesNegativePrompt)
  }

  @Test func anUnknownFamilyShowsEverything() {
    #expect(FamilyTraits.of(nil) == .all)
    #expect(FamilyTraits.of("some_future_model") == .all)
  }
}

struct LoRACompatibilityTests {
  let catalog = ModelCatalog(
    models: [],
    loras: [
      CatalogLoRA(file: "b.safetensors", name: "Beta", family: "flux2_9b"),
      CatalogLoRA(file: "a.safetensors", name: "Alpha", family: "flux2_9b"),
      CatalogLoRA(file: "q.safetensors", name: "Qwen style", family: "qwen_image"),
      CatalogLoRA(file: "u.safetensors", name: "Unknown", family: nil),
    ],
    fileCount: 4)

  @Test func offersTheFamilyThenTheUnknownOnes() {
    #expect(catalog.loras(for: "flux2_9b").map(\.name) == ["Alpha", "Beta", "Unknown"])
  }

  @Test func offersEverythingForAnUnknownModelFamily() {
    #expect(catalog.loras(for: nil).count == 4)
  }

  @Test func statusSaysWhyALoRAIsNotSent() {
    #expect(catalog.status(of: LoRASelection(file: "a.safetensors"), family: "flux2_9b") == .usable)
    #expect(catalog.status(of: LoRASelection(file: "u.safetensors"), family: "flux2_9b") == .usable)
    #expect(catalog.status(of: LoRASelection(file: "q.safetensors"), family: "flux2_9b") == .otherFamily("qwen_image"))
    #expect(catalog.status(of: LoRASelection(file: "gone.safetensors"), family: "flux2_9b") == .notOnServer)
  }
}
