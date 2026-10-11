import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMaster

@Suite("The brief for the language model")
struct BriefTests {
  private let families = PMData.embeddedFamilies
  private func emptyFolder() -> DTHubPromptFolder {
    DTHubPromptFolder(folder: FileManager.default.temporaryDirectory.appendingPathComponent("pm-brief-\(UUID().uuidString)"))
  }

  private func guide(_ family: String, familyPrompt: String?? = nil) -> DTHubPromptGuide {
    let known = Fixtures.appFamilies[family]!
    return DTHubPromptGuide(
      label: known.label, usesNegative: known.negative, notes: "", familyPrompt: familyPrompt ?? known.familyPrompt)
  }

  private func make(
    _ family: String, folder: DTHubPromptFolder? = nil, booru: Bool = false, familyPrompt: String?? = nil
  ) -> Brief? {
    BriefBuilder.make(
      guide: guide(family, familyPrompt: familyPrompt), family: family, data: families, folder: folder ?? emptyFolder(),
      description: "ciao", terms: [], booru: booru)
  }
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

  @Test func everyFamilyStartsWithTheSameTwoParagraphsAsBeforeAndKeepsTheFamilyNotes() throws {
    for family in PMFamilies.all {
      let system = try #require(make(family)).system
      let old = try #require(Fixtures.oldSystems[family])
      let head = old.components(separatedBy: "\n\n").prefix(2).joined(separator: "\n\n")
      #expect(system.hasPrefix(head), Comment(rawValue: family))
      let notes = try #require(old.range(of: "Model notes:\n").map { String(old[$0.upperBound...]) })
      // The old text ended, on four families, with a note for the reviewers that no longer goes to the model.
      let clean = notes.components(separatedBy: "\n(Provisional master prompt").first ?? notes
      #expect(system.contains(clean), Comment(rawValue: family))
      #expect(system.contains("exclusively in English"), Comment(rawValue: family))
    }
  }

  @Test func theFamiliesWrittenInTagsUseTheTagsRules() throws {
    for family in PMFamilies.all {
      let system = try #require(make(family)).system
      #expect(system.contains("Do not add subjects") == (families.families[family]?.tags == true), Comment(rawValue: family))
      #expect(system.contains("Enrich the description") == (families.families[family]?.tags != true), Comment(rawValue: family))
    }
    #expect(Set(families.families.filter { $0.value.tags == true }.keys) == ["sdxl_base_v0.9", "v1", "cosmos2.5_2b"])
  }

  @Test func theRulesCarryTheLabelAndNoPlaceholderIsLeft() throws {
    let system = try #require(make("qwen_image_2.1")).system
    #expect(system.hasPrefix("You write prompts for the image model \"Qwen Image 2.1\"."))
    #expect(!system.contains("{label}") && !system.contains("{words}") && !system.contains("{maxWords}"))
  }

  @Test func theBooruRuleComesAfterTheFamilyTextAndOnlyWhenOnAndOnlyWhereThereIsOne() throws {
    let on = try #require(make("v1", booru: true)).system
    #expect(on.hasSuffix(families.families["v1"]!.booruSystem!))
    let off = try #require(make("v1", booru: false)).system
    #expect(!off.contains("Tag mode is ON") && on.hasPrefix(off))
    let flux = try #require(make("flux1", booru: true)).system
    #expect(flux == (try #require(make("flux1", booru: false)).system))  // no switch on this family
  }

  @Test func theUsersFileComesLastAfterThePriorityLine() throws {
    let folder = emptyFolder()
    try FileManager.default.createDirectory(at: folder.folder.appendingPathComponent("custom"), withIntermediateDirectories: true)
    try "Always rhyme.".write(to: folder.folder.appendingPathComponent("custom/compose.md"), atomically: true, encoding: .utf8)
    let plain = try #require(make("v1", booru: true)).system
    let mine = try #require(make("v1", folder: folder, booru: true)).system
    #expect(mine == plain + "\n\n" + DTHubPromptFolder.priorityLine + "\n\nAlways rhyme.")
  }

  @Test func theUsersFileCanReplaceTheRules() throws {
    let folder = emptyFolder()
    try FileManager.default.createDirectory(at: folder.folder.appendingPathComponent("custom"), withIntermediateDirectories: true)
    try "---\nmode: replace\n---\nMy rules for {label}.".write(
      to: folder.folder.appendingPathComponent("custom/compose.md"), atomically: true, encoding: .utf8)
    let system = try #require(make("flux2_9b", folder: folder)).system
    #expect(system.hasPrefix("My rules for FLUX.2 [klein] 9B.\n\nThe final prompt must be written"))
  }

  @Test func withoutAFamilyPromptThereIsNoBrief() {
    #expect(make("flux2_9b", familyPrompt: .some(nil)) == nil)
    #expect(make("flux2_9b", familyPrompt: .some("  \n")) == nil)
  }
}
