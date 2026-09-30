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

struct JobComposerTests {
  let catalog = ModelCatalog(
    models: [],
    loras: [
      CatalogLoRA(file: "a.safetensors", name: "Alpha", family: "flux2_9b"),
      CatalogLoRA(file: "q.safetensors", name: "Qwen style", family: "qwen_image"),
    ],
    fileCount: 2)

  func compose(family: String?, _ parameters: GenerationParameters) -> [GenerationJob] {
    JobComposer.batches(
      prompt: "fox", negativePrompt: "blurry", model: "m.ckpt", family: family,
      parameters: parameters, catalog: catalog) { 7 }
  }

  @Test func sendsOnlyTheUsableLoRAs() {
    let parameters = GenerationParameters(loras: [
      LoRASelection(file: "a.safetensors", weight: 0.8), LoRASelection(file: "q.safetensors"),
      LoRASelection(file: "gone.safetensors"),
    ])
    let jobs = compose(family: "flux2_9b", parameters)
    #expect(jobs[0].parameters.loras == [LoRASelection(file: "a.safetensors", weight: 0.8)])
  }

  @Test func keepsTheNegativePromptWhereTheFamilyUsesIt() {
    #expect(compose(family: "sdxl_base_v0.9", .default)[0].negativePrompt == "blurry")
    #expect(compose(family: "seedvr2_7b", .default)[0].negativePrompt == "")
  }

  @Test func turnsCFGZeroOffWhereTheFamilyHasNoShift() {
    let parameters = GenerationParameters(cfgZeroStar: true)
    #expect(!compose(family: "v1", parameters)[0].parameters.cfgZeroStar)
    #expect(compose(family: "flux2_9b", parameters)[0].parameters.cfgZeroStar)
  }

  @Test func splitsIntoBatchesWithTheirSeeds() {
    let jobs = compose(family: "flux2_9b", GenerationParameters(seed: 3, randomSeed: false, batchCount: 2))
    #expect(jobs.map(\.parameters.seed) == [3, 4])
    #expect(jobs.allSatisfy { $0.prompt == "fox" && $0.model == "m.ckpt" })
  }
}
