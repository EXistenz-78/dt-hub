import Foundation
import Testing

@testable import HubCore

struct EmbeddedPromptsTests {
  @Test func seventeenFamiliesAllParseAsValid() {
    #expect(EmbeddedPrompts.families.count == 17)
    for (id, text) in EmbeddedPrompts.families {
      let file = PromptFile.parse(text)
      #expect(file.isValid, "\(id)")
      #expect(["label", "negative", "words", "maxWords", "version"].allSatisfy { file.header[$0] != nil }, "\(id)")
    }
    for id in ["minimax_h3", "ltx2.3"] {
      let file = PromptFile.parse(EmbeddedPrompts.families[id] ?? "")
      #expect(file.isValid && file.header["kind"] == "video" && file.header["version"] == "1", "\(id)")
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

  @Test func miniMaxH3IsAVideoFamilyWithPictureTags() {
    let family = PromptLibrary.builtIn.family("minimax_h3")
    #expect(family?.label == "MiniMax H3")
    #expect(family?.negative == false && family?.isVideo == true)
    #expect(family?.words == "80-250" && family?.maxWords == "350")
    #expect(family?.body.contains("{words}") == false)
    #expect(family?.body.contains("<Picture 1>") == true)
    #expect(family?.body.contains("Image 1: the start image") == true)
    #expect(family?.body.contains("[Shot 1]") == true)
  }

  @Test func ltx23IsAVideoFamilyThatAsksForSoundAndNoMusic() {
    let family = PromptLibrary.builtIn.family("ltx2.3")
    #expect(family?.label == "LTX-2.3")
    #expect(family?.negative == false && family?.isVideo == true)
    #expect(family?.words == "80-180" && family?.maxWords == "220")
    #expect(family?.body.contains("Image 1: the start image") == true)
    #expect(family?.body.contains("no music") == true)
  }

  @Test func imageFamiliesAreNotVideo() {
    #expect(PromptLibrary.builtIn.families().filter(\.isVideo).map(\.id).sorted() == ["ltx2.3", "minimax_h3"])
  }

  @Test func theRulesNameAVideoModelOnlyForAVideoFamily() {
    let library = PromptLibrary.builtIn
    for task in PromptTask.allCases {
      let video = library.system(task: task, family: "minimax_h3")
      #expect(video.contains("video model") && !video.contains("image model"))
      #expect(video.hasPrefix("You write prompts for the video model \"MiniMax H3\"."))
      #expect(library.system(task: task, family: "flux2_9b").contains("image model"))
      #expect(!library.system(task: task, family: "flux2_9b").contains("video model"))
    }
  }

  @Test func installWritesTheVideoFamiliesAndListsThem() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("prompt-video-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    PromptLibrary(folder: dir).install()
    for id in ["minimax_h3", "ltx2.3"] {
      #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("family/\(id).md").path), "\(id)")
    }
    let list = try String(contentsOf: dir.appendingPathComponent("custom/families.txt"), encoding: .utf8)
    #expect(list.contains("MiniMax H3 = minimax_h3 (no negative prompt)"))
    #expect(list.contains("LTX-2.3 = ltx2.3 (no negative prompt)"))
  }
}
