import Foundation
import Testing

@testable import HubCore

/// Enhance/Generate Prompt read the prompts from the library (spec «Prompt modulari», §5).
struct PromptBriefLibraryTests {
  func library(_ files: [String: String] = [:]) throws -> PromptLibrary {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("brief-lib-\(UUID().uuidString)")
    for (path, text) in files {
      let url = dir.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try text.write(to: url, atomically: true, encoding: .utf8)
    }
    return PromptLibrary(folder: dir)
  }

  let pair = PromptPair(prompt: "un gatto", negative: "sfocato")

  @Test func enhanceUsesTheLibrarySystem() throws {
    let mine = try library(["custom/enhance.md": "Sempre in rima."])
    let request = PromptBrief.enhance(pair, family: "flux2", library: mine)
    #expect(request.options.system?.hasSuffix(PromptLibrary.priorityLine + "\n\nSempre in rima.") == true)
    #expect(PromptBrief.enhance(pair, family: "flux2").options.system == LegacySystemPrompts.byFamily["flux2"])
  }

  @Test func describeUsesTheDescribeRules() throws {
    let mine = try library(["custom/describe.md": "Solo colori."])
    let url = URL(fileURLWithPath: "/tmp/x.png")
    #expect(PromptBrief.describe(imageAt: url, family: "flux2", library: mine).options.system?.hasSuffix("Solo colori.") == true)
    #expect(PromptBrief.enhance(pair, family: "flux2", library: mine).options.system?.contains("Solo colori.") == false)
  }

  @Test func ownSystemGetsTheCustomAdditionOnly() throws {
    let mine = try library(["custom/enhance.md": "Aggiunta."])
    let with = PromptBrief.enhance(pair, ownSystem: "PE rules", generation: nil, library: mine)
    #expect(with.options.system == "PE rules\n\n" + PromptLibrary.priorityLine + "\n\nAggiunta.")
    #expect(with.prompt == "un gatto")
    #expect(PromptBrief.enhance(pair, ownSystem: "PE rules", generation: nil).options.system == "PE rules")
  }

  @Test func theNegativePromptFollowsTheFamilyFile() throws {
    let file = "---\nlabel: Flux mio\nmaxWords: 9\nnegative: true\nversion: 1\nwords: 1-2\n---\nRisposta JSON."
    let mine = try library(["family/flux2.md": file])
    #expect(PromptBrief.enhance(pair, family: "flux2", library: mine).prompt.contains("Negative prompt:\nsfocato"))
    #expect(!PromptBrief.enhance(pair, family: "flux2").prompt.contains("Negative prompt:"))
  }

  @Test func theFamilyMenuListsTheLibraryAndTheUnknownCatalogOnes() throws {
    let list = LanguageModelFamilyOptions.list(catalogFamilies: ["flux2", "nuova_famiglia"], library: try library())
    #expect(list.count == 18)
    #expect(list.first { $0.key == "nuova_famiglia" }?.label == "nuova_famiglia")
    #expect(list.first { $0.key == "flux2" }?.label == "FLUX.2 [dev]")
  }
}
