import Testing

@testable import Panorama360F3

struct PFPromptTests {
  @Test func oneImage() {
    #expect(PFPrompt.panorama(imageCount: 1, description: "") == "starting from <image 1>")
  }

  @Test func threeImages() {
    #expect(PFPrompt.references(count: 3) == "starting from <image 1>, <image 2>, <image 3>")
  }

  @Test func descriptionAfterADotAndASpace() {
    #expect(
      PFPrompt.panorama(imageCount: 2, description: "foggy cemetery at night")
        == "starting from <image 1>, <image 2>. foggy cemetery at night")
  }

  @Test func aBlankDescriptionAddsNothing() {
    #expect(PFPrompt.panorama(imageCount: 2, description: "  \n") == "starting from <image 1>, <image 2>")
  }

  @Test func theDescriptionIsTrimmed() {
    #expect(PFPrompt.panorama(imageCount: 1, description: "\n  misty lake \n") == "starting from <image 1>. misty lake")
  }

  @Test func noImagesGivesAnEmptyString() {
    #expect(PFPrompt.panorama(imageCount: 0, description: "anything") == "")
    #expect(PFPrompt.references(count: 0) == "")
  }
}
