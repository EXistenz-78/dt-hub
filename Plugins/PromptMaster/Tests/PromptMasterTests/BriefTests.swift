import Foundation
import Testing

@testable import PromptMaster

@Suite("The brief for the language model")
struct BriefTests {
  private let masters = PMData.embeddedMasters
  private func term(_ id: String, _ english: String, in category: String = "Light Source", avoid: Bool = false) -> SelectedTerm {
    SelectedTerm(id: id, title: english, categoryTitle: "C", categoryEnglish: category, english: english, isNegative: avoid)
  }

  @Test func theRequestHasTheDescriptionAsWrittenAndTheTermsInEnglishWithTheirCategory() {
    let text = BriefBuilder.request(
      description: "  Un vecchio pescatore al molo, all'alba  ",
      terms: [
        term("a", "Starlight"), term("b", "Jewel tones", in: "Color Palette"),
        term("c", "Folk horror", in: "Genres & Aesthetics"), term("d", "Blurry", in: "Negative Terms", avoid: true),
      ])
    #expect(
      text == """
        Description (any language):
        Un vecchio pescatore al molo, all'alba

        Terms to include:
        - Light Source: Starlight
        - Color Palette: Jewel tones
        - Genres & Aesthetics: Folk horror

        Terms to avoid:
        - Negative Terms: Blurry
        """)
  }

  @Test func termsOfOneCategoryShareALineInTheirOrder() {
    let text = BriefBuilder.request(
      description: "x", terms: [term("a", "Starlight"), term("b", "Candlelight"), term("c", "Jewel tones", in: "Color Palette")])
    #expect(text.contains("- Light Source: Starlight, Candlelight\n- Color Palette: Jewel tones"))
  }

  @Test func aTermWithoutACategoryIsListedAlone() {
    #expect(BriefBuilder.request(description: "x", terms: [term("a", "Fog", in: "")]).hasSuffix("Terms to include:\n- Fog"))
  }

  @Test func theBriefOfRealTermsNamesTheirCategories() {
    let database = PMData.embeddedDatabase
    func id(_ english: String) -> String { database.categories.flatMap(\.terms).first { $0.en == english }!.id }
    let tree = TermTree(database: database, custom: [], hidden: [], italian: true)
    let chosen = tree.selectedTerms([id("Starlight"), id("Jewel tones"), id("Folk horror")])
    let text = BriefBuilder.request(description: "x", terms: chosen)
    #expect(text.contains("- Light Source: Starlight") && text.contains("- Color Palette: Jewel tones"))
    #expect(text.contains("- Genres & Aesthetics: Folk horror"))
    #expect(BriefBuilder.enhancerRequest(description: "x", terms: chosen).hasSuffix(
      "Look: light source: Starlight; color palette: Jewel tones; genres & aesthetics: Folk horror."))
  }

  @Test func aCustomTermTakesTheCategoryItWasAddedTo() {
    let custom = [CustomTerm(id: "custom-1", categoryID: "light_source", text: "luce da finestra")]
    let tree = TermTree(database: PMData.embeddedDatabase, custom: custom, hidden: [], italian: true)
    let text = BriefBuilder.request(description: "x", terms: tree.selectedTerms(["custom-1"]))
    #expect(text.hasSuffix("- Light Source: luce da finestra"))
  }

  // MARK: The request for the prompt enhancer

  @Test func theEnhancerGetsTheDescriptionAndOneLookLine() {
    let text = BriefBuilder.enhancerRequest(
      description: "  Un vecchio pescatore al molo  ",
      terms: [
        term("a", "Starlight"), term("b", "Candlelight"), term("c", "Jewel tones", in: "Color Palette"),
        term("d", "Blurry", in: "Negative Terms", avoid: true),
      ])
    #expect(
      text == """
        Un vecchio pescatore al molo

        Look: light source: Starlight, Candlelight; color palette: Jewel tones.
        """)
  }

  @Test func theEnhancerRequestWithOnlyADescriptionOrOnlyTermsOrNeither() {
    #expect(BriefBuilder.enhancerRequest(description: " a cat ", terms: []) == "a cat")
    #expect(BriefBuilder.enhancerRequest(description: "", terms: [term("a", "Fog", in: "Mood")]) == "Look: mood: Fog.")
    #expect(BriefBuilder.enhancerRequest(description: "a cat", terms: [term("a", "Blurry", avoid: true)]) == "a cat")
    #expect(BriefBuilder.enhancerRequest(description: " ", terms: []).isEmpty)
  }

  @Test func withoutADescriptionTheModelIsToldToUseTheTermsAlone() {
    let text = BriefBuilder.request(description: " \n ", terms: [term("a", "Fog")])
    #expect(text.contains("(none: build the image from the terms alone)") && text.contains("- Light Source: Fog"))
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
