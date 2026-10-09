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

struct PromptBriefOwnSystemTests {
  @Test func enhanceSendsTheTextAsItIsWithTheModelsOwnOptions() {
    let g = LanguageModelProfile.Generation(temperature: 0.7, topP: 0.8, topK: 20)
    let r = PromptBrief.enhance(PromptPair(prompt: "gatto", negative: "n"), ownSystem: "S", generation: g)
    #expect(r.prompt == "gatto" && r.images.isEmpty)
    #expect(
      r.options == LanguageModelOptions(system: "S", temperature: 0.7, topP: 0.8, topK: 20, maxTokens: 16384, thinking: true))
    let bare = PromptBrief.enhance(PromptPair(prompt: "a", negative: ""), ownSystem: "S", generation: nil)
    #expect(bare.options == LanguageModelOptions(system: "S", maxTokens: 16384, thinking: true))
  }

  @Test func describeSendsTheImageAndAFixedSentence() {
    let url = URL(fileURLWithPath: "/tmp/i.png")
    let r = PromptBrief.describe(imageAt: url, ownSystem: "S", generation: nil)
    #expect(r.prompt == "Describe this image as a prompt for an image-generation model.")
    #expect(r.images == [url])
    #expect(r.options.system == "S" && r.options.thinking == true)
  }
}

struct PromptBriefImagesTests {
  let a = URL(fileURLWithPath: "/tmp/a.png")
  let b = URL(fileURLWithPath: "/tmp/b.png")
  let current = PromptPair(prompt: "put the cat from image 2 on image 1", negative: "blurry")
  let block =
    "Attached images:\n- Image 1: the start image (the picture being edited).\n- Image 2: reference image 1.\n\nThe prompt refers to these images. Look at them to make the description concrete and accurate, and keep every reference to an image (image 1, image 2…) exactly as written.\n\n"

  @Test func labelsFollowDrawThingsNumbering() {
    #expect(
      PromptBrief.imageLabels(hasStart: true, references: 2) == [
        "Image 1: the start image (the picture being edited).", "Image 2: reference image 1.", "Image 3: reference image 2.",
      ])
    #expect(
      PromptBrief.imageLabels(hasStart: false, references: 2) == [
        "Image 1: reference image 1.", "Image 2: reference image 2.",
      ])
    #expect(PromptBrief.imageLabels(hasStart: true, references: 0) == ["Image 1: the start image (the picture being edited)."])
    #expect(PromptBrief.imageLabels(hasStart: false, references: 0).isEmpty)
  }

  @Test func theImagesGoInOrderWithTheBlockBeforeTheUsualRequest() {
    let images = EnhanceImages(start: a, references: [b])
    #expect(images.all == [a, b] && !images.isEmpty)
    let request = PromptBrief.enhance(current, family: "flux2", images: images)
    #expect(request.images == [a, b])
    #expect(request.prompt == block + PromptBrief.enhance(current, family: "flux2").prompt)
    #expect(request.options == PromptBrief.enhance(current, family: "flux2").options)
  }

  @Test func noImagesIsTheRequestOfToday() {
    #expect(EnhanceImages().isEmpty)
    #expect(PromptBrief.enhance(current, family: "flux2", images: EnhanceImages()) == PromptBrief.enhance(current, family: "flux2"))
    let g = LanguageModelProfile.Generation(temperature: 0.5)
    #expect(
      PromptBrief.enhance(current, ownSystem: "S", generation: g, images: EnhanceImages())
        == PromptBrief.enhance(current, ownSystem: "S", generation: g))
  }

  @Test func aStartImageAloneAndReferencesAlone() {
    let onlyStart = PromptBrief.enhance(current, family: nil, images: EnhanceImages(start: a))
    #expect(onlyStart.images == [a] && onlyStart.prompt.hasPrefix("Attached images:\n- Image 1: the start image"))
    let onlyRefs = PromptBrief.enhance(current, family: nil, images: EnhanceImages(references: [a, b]))
    #expect(onlyRefs.images == [a, b])
    #expect(onlyRefs.prompt.hasPrefix("Attached images:\n- Image 1: reference image 1.\n- Image 2: reference image 2.\n\n"))
  }

  @Test func anOwnSystemPromptGetsTheBlockAndTheUsersText() {
    let g = LanguageModelProfile.Generation(temperature: 0.7)
    let request = PromptBrief.enhance(current, ownSystem: "S", generation: g, images: EnhanceImages(start: a, references: [b]))
    #expect(request.prompt == block + current.prompt)
    #expect(request.images == [a, b])
    #expect(request.options == PromptBrief.enhance(current, ownSystem: "S", generation: g).options)
  }
}
