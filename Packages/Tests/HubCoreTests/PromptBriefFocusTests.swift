import Foundation
import Testing

@testable import HubCore

/// Generate Prompt from a picture dropped on «Soggetto» or «Stile»: the usual describe request plus one sentence that says
/// what to take from the picture and what from the text of the prompt field.
struct PromptBriefFocusTests {
  let url = URL(fileURLWithPath: "/tmp/a.png")
  let withText = PromptPair(prompt: "a knight in the rain", negative: "")
  let noText = PromptPair(prompt: "  ", negative: "")
  let familyBase =
    "Describe this image as a prompt for this model, following the model notes. Describe only what is visible; do not invent a story."

  @Test func subjectTakesTheSubjectSettingAndActionFromThePictureAndTheStyleFromTheText() {
    let r = PromptBrief.describe(imageAt: url, current: withText, family: "krea_2", focus: .subject)
    #expect(r.prompt.hasPrefix(familyBase))
    #expect(r.prompt.contains("ONLY the subject, the setting and the action"))
    #expect(r.prompt.contains("take the style from the user's text"))
    #expect(r.prompt.hasSuffix("User's text:\na knight in the rain"))
    #expect(r.images == [url])
  }

  @Test func styleTakesTheStyleFromThePictureAndTheSubjectFromTheText() {
    let r = PromptBrief.describe(imageAt: url, current: withText, family: "krea_2", focus: .style)
    #expect(r.prompt.hasPrefix(familyBase))
    #expect(r.prompt.contains("ONLY the style"))
    #expect(r.prompt.contains("take the subject, the setting and the action from the user's text"))
    #expect(r.prompt.hasSuffix("User's text:\na knight in the rain"))
  }

  @Test func withoutTextThereIsNoUserTextBlock() {
    for focus in [DescribeFocus.subject, .style] {
      let r = PromptBrief.describe(imageAt: url, current: noText, family: "krea_2", focus: focus)
      #expect(!r.prompt.contains("User's text"))
    }
  }

  @Test func theOptionsAreThoseOfTheUsualDescribe() {
    let usual = PromptBrief.describe(imageAt: url, family: "krea_2")
    let focused = PromptBrief.describe(imageAt: url, current: withText, family: "krea_2", focus: .style)
    #expect(focused.options == usual.options)
  }

  @Test func anLLMWithItsOwnSystemGetsTheSameSentences() {
    let r = PromptBrief.describe(
      imageAt: url, ownSystem: "S", generation: nil, current: withText, focus: .subject)
    #expect(r.prompt.hasPrefix("Describe this image as a prompt for an image-generation model."))
    #expect(r.prompt.contains("ONLY the subject, the setting and the action"))
    #expect(r.prompt.hasSuffix("User's text:\na knight in the rain"))
    #expect(r.images == [url] && r.options.system?.hasPrefix("S") == true)
  }

  @Test func thePUPGetsThemInsideItsScaffold() {
    let pup = LanguageModelProfile.Pup(t2i: "T2I SYS", i2i: "I2I SYS")
    let r = PromptBrief.describe(imageAt: url, current: withText, pup: pup, focus: .style)
    #expect(r.prompt.hasPrefix("Reference images follow in order"))
    #expect(r.prompt.contains("ONLY the style"))
    #expect(r.prompt.contains("User's text:\na knight in the rain"))
    #expect(r.prompt.hasSuffix("Output the caption."))
    #expect(r.images == [url] && r.options.system == "I2I SYS")
  }
}
