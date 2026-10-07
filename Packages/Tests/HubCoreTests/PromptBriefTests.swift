import Foundation
import HubKit
import Testing

@testable import HubCore

struct PromptBriefTests {
  @Test func systemForAFamilyWithoutNegative() {
    let system = PromptBrief.system(family: "flux2_9b")
    #expect(system.hasPrefix("You write prompts for the image model \"FLUX.2 [klein] 9B\"."))
    #expect(system.contains("exclusively in English"))
    #expect(system.contains("Reply with the prompt only"))
    #expect(!system.contains("JSON"))
    #expect(system.hasSuffix("\n\nModel notes:\n" + PromptGuides.all["flux2_9b"]!.notes))
  }

  @Test func systemForAFamilyWithNegativeAsksForJSON() {
    let system = PromptBrief.system(family: "v1")
    #expect(system.contains("{\"prompt\": \"...\", \"negative\": \"...\"}"))
    #expect(system.contains("Both values are in English"))
    #expect(!system.contains("Reply with the prompt only"))
  }

  @Test func systemForAnUnknownFamilyIsGenericProse() {
    for family in ["mystery", nil] as [String?] {
      let system = PromptBrief.system(family: family)
      #expect(system.hasPrefix("You write prompts for an image-generation model."))
      #expect(system.contains("Reply with the prompt only"))
      #expect(!system.contains("Model notes:"))
    }
  }

  @Test func enhanceRequestText() {
    let request = PromptBrief.enhance(PromptPair(prompt: "un gatto sul tetto", negative: ""), family: "flux2")
    #expect(
      request.prompt
        == "Improve the prompt below for this model. Keep every element it describes and never contradict it; add concrete visual detail as the model notes ask. The prompt may be in any language.\n\nPrompt:\nun gatto sul tetto"
    )
    #expect(request.images.isEmpty)
    #expect(
      request.options
        == LanguageModelOptions(system: PromptBrief.system(family: "flux2"), maxTokens: 2048, thinking: false))
  }

  @Test func enhanceAddsTheNegativeOnlyWhenTheFamilyUsesItAndItIsNotEmpty() {
    let withNegative = PromptBrief.enhance(PromptPair(prompt: "a cat", negative: "blurry"), family: "v1")
    #expect(withNegative.prompt.hasSuffix("\n\nNegative prompt:\nblurry"))
    let emptyNegative = PromptBrief.enhance(PromptPair(prompt: "a cat", negative: ""), family: "v1")
    #expect(!emptyNegative.prompt.contains("Negative prompt:"))
    let noNegativeFamily = PromptBrief.enhance(PromptPair(prompt: "a cat", negative: "blurry"), family: "flux2")
    #expect(!noNegativeFamily.prompt.contains("Negative prompt:"))
  }

  @Test func describeRequest() {
    let url = URL(fileURLWithPath: "/tmp/a.png")
    let request = PromptBrief.describe(imageAt: url, family: "krea_2")
    #expect(
      request.prompt
        == "Describe this image as a prompt for this model, following the model notes. Describe only what is visible; do not invent a story."
    )
    #expect(request.images == [url])
    #expect(request.options.system == PromptBrief.system(family: "krea_2"))
    #expect(request.options.maxTokens == 2048)
    #expect(request.options.thinking == false)
  }
}
