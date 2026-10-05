import Foundation
import Testing

@testable import PromptMaster

@Suite("The brief for the language model")
struct BriefTests {
  private let masters = PMData.embeddedMasters
  private func term(_ id: String, _ english: String, avoid: Bool = false) -> SelectedTerm {
    SelectedTerm(id: id, title: english, categoryTitle: "C", english: english, isNegative: avoid)
  }

  @Test func theRequestHasTheDescriptionAsWrittenAndTheTermsInEnglish() {
    let text = BriefBuilder.request(
      description: "  Un vecchio pescatore al molo, all'alba  ",
      terms: [term("a", "Extreme close-up"), term("b", "Soft diffused light"), term("c", "Blurry", avoid: true)])
    #expect(
      text == """
        Description (any language):
        Un vecchio pescatore al molo, all'alba

        Terms to include:
        - Extreme close-up
        - Soft diffused light

        Terms to avoid:
        - Blurry
        """)
  }

  @Test func withoutADescriptionTheModelIsToldToUseTheTermsAlone() {
    let text = BriefBuilder.request(description: " \n ", terms: [term("a", "Fog")])
    #expect(text.contains("(none: build the image from the terms alone)") && text.contains("- Fog"))
    #expect(!text.contains("Terms to avoid"))
  }

  @Test func withoutTermsThereIsNoTermsSection() {
    let text = BriefBuilder.request(description: "a cat", terms: [])
    #expect(text == "Description (any language):\na cat")
  }

  @Test func theSystemPromptIsTheFamilysAndAsksForEnglish() throws {
    let brief = try #require(
      BriefBuilder.make(family: "flux2_9b", masters: masters, description: "ciao", terms: [], booru: false))
    #expect(brief.system == masters.families["flux2_9b"]?.system)
    #expect(brief.system.contains("exclusively in English"))
  }

  @Test func theBooruRuleIsAddedOnlyWhenOnAndOnlyWhereThereIsOne() throws {
    let on = try #require(BriefBuilder.make(family: "v1", masters: masters, description: "x", terms: [], booru: true))
    #expect(on.system.hasSuffix(masters.families["v1"]!.booruSystem!))
    let off = try #require(BriefBuilder.make(family: "v1", masters: masters, description: "x", terms: [], booru: false))
    #expect(off.system == masters.families["v1"]?.system)
    let flux = try #require(BriefBuilder.make(family: "flux1", masters: masters, description: "x", terms: [], booru: true))
    #expect(flux.system == masters.families["flux1"]?.system)  // no switch on this family
  }

  @Test func aFamilyWithoutAMasterPromptHasNoBrief() {
    #expect(BriefBuilder.make(family: "ideogram_4", masters: masters, description: "x", terms: [], booru: false) == nil)
  }
}
