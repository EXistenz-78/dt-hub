import Testing

@testable import HubCore

struct EmbeddedPromptsTests {
  @Test func fifteenFamiliesAllParseAsValid() {
    #expect(EmbeddedPrompts.families.count == 15)
    for (id, text) in EmbeddedPrompts.families {
      let file = PromptFile.parse(text)
      #expect(file.isValid, "\(id)")
      #expect(["label", "negative", "words", "maxWords", "version"].allSatisfy { file.header[$0] != nil }, "\(id)")
    }
  }

  @Test func eachFamilyAssemblesToTheSystemPromptOfToday() {
    let rules = PromptFile.parse(EmbeddedPrompts.rules["enhance"] ?? "")
    for (id, text) in EmbeddedPrompts.families where LegacySystemPrompts.byFamily[id] != nil {
      let family = PromptFile.parse(text)
      let values = [
        "label": family.header["label"] ?? "", "words": family.header["words"] ?? "",
        "maxWords": family.header["maxWords"] ?? "",
      ]
      let system = rules.resolved(values) + "\n\n" + family.resolved(values)
      #expect(system == LegacySystemPrompts.byFamily[id], "\(id)")
    }
    #expect(Set(LegacySystemPrompts.byFamily.keys).isSubset(of: Set(EmbeddedPrompts.families.keys)))
  }

  @Test func flux3ReadsNaturalProseAndTakesNoNegative() {
    let family = PromptLibrary.builtIn.family("flux3_5b")
    #expect(family?.label == "FLUX.3 [klein]")
    #expect(family?.negative == false)
    #expect(family?.words == "60-250" && family?.maxWords == "500")
    #expect(family?.body.contains("8192 tokens") == true)
    #expect(family?.body.contains("{words}") == false)
  }

  @Test func mossAsksForAJSONReplyWithANegative() {
    let family = PromptLibrary.builtIn.family("moss_image")
    #expect(family?.label == "MOSS Image")
    #expect(family?.negative == true)
    #expect(family?.words == "60-200" && family?.maxWords == "400")
    #expect(family?.body.contains("4096 tokens") == true)
    #expect(family?.body.contains("nsfw, worst quality, bad anatomy, watermark, jpeg artifact") == true)
  }

  @Test func theCamelCaseMossIdFindsTheSameFamily() {
    let library = PromptLibrary.builtIn
    #expect(library.family("mossImage") == library.family("moss_image"))
    #expect(library.family("mossImage") != nil)
    #expect(library.system(task: .enhance, family: "mossImage") == library.system(task: .enhance, family: "moss_image"))
  }

  @Test func theGenericOneEqualsToday() {
    let body = PromptFile.parse(EmbeddedPrompts.genericFamily).body
    #expect(EmbeddedPrompts.genericIntro + "\n\n" + body == LegacySystemPrompts.generic)
  }

  @Test func enhanceAndDescribeRulesAreValid() {
    for name in ["enhance", "describe"] {
      #expect(PromptFile.parse(EmbeddedPrompts.rules[name] ?? "").isValid, Comment(rawValue: name))
    }
  }
}
