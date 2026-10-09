import Foundation
import HubKit
import Testing

@testable import HubCore

struct LanguageModelProfileTests {
  func folder(_ files: [String: String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LMProfile-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, text) in files { try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
    return dir
  }

  @Test func genericPromptServesBothTasksTrimmed() throws {
    let p = LanguageModelProfile.load(folder: try folder(["system_prompt.txt": "\n  Be brief.  \n"]))
    #expect(p.systemPrompt(for: .enhance) == "Be brief.")
    #expect(p.systemPrompt(for: .describe) == "Be brief.")
  }

  @Test func specificPromptsBeatTheGenericOne() throws {
    let p = LanguageModelProfile.load(
      folder: try folder(["system_prompt.txt": "G", "system_prompt_t2i.txt": "T", "system_prompt_i2i.txt": "I"]))
    #expect(p.systemPrompt(for: .enhance) == "T")
    #expect(p.systemPrompt(for: .describe) == "I")
    let onlyT = LanguageModelProfile.load(folder: try folder(["system_prompt_t2i.txt": "T", "system_prompt.txt": "G"]))
    #expect(onlyT.systemPrompt(for: .describe) == "G")
  }

  @Test func emptyOrBlankFilesCountAsMissing() throws {
    let p = LanguageModelProfile.load(
      folder: try folder(["system_prompt_t2i.txt": "  \n", "system_prompt.txt": "G"]))
    #expect(p.systemPrompt(for: .enhance) == "G")
    let none = LanguageModelProfile.load(folder: try folder(["system_prompt.txt": ""]))
    #expect(none.systemPrompt(for: .enhance) == nil)
  }

  @Test func generationConfigIsReadPartially() throws {
    let full = LanguageModelProfile.load(
      folder: try folder(["generation_config.json": #"{"temperature":0.7,"top_p":0.8,"top_k":20,"max_new_tokens":512}"#]))
    #expect(full.generation == .init(temperature: 0.7, topP: 0.8, topK: 20))
    let part = LanguageModelProfile.load(folder: try folder(["generation_config.json": #"{"temperature":0.5}"#]))
    #expect(part.generation == .init(temperature: 0.5, topP: nil, topK: nil))
  }

  @Test func brokenOrMissingFilesGiveNothing() throws {
    let broken = LanguageModelProfile.load(folder: try folder(["generation_config.json": "{nope"]))
    #expect(broken.generation == nil)
    let empty = LanguageModelProfile.load(folder: try folder([:]))
    #expect(empty.generation == nil && empty.systemPrompt(for: .enhance) == nil && empty.systemPrompt(for: .describe) == nil)
  }

  @Test func aConfigWithNoSamplingValuesGivesNil() throws {
    let p = LanguageModelProfile.load(folder: try folder(["generation_config.json": #"{"use_cache":true}"#]))
    #expect(p.generation == nil)
  }

  @Test func withImagesEnhanceUsesTheImageToImagePrompt() throws {
    let both = LanguageModelProfile.load(folder: try folder(["system_prompt_t2i.txt": "T", "system_prompt_i2i.txt": "I"]))
    #expect(both.systemPrompt(for: .enhance, withImages: true) == "I")
    #expect(both.systemPrompt(for: .enhance, withImages: false) == "T")
    #expect(both.systemPrompt(for: .enhance) == "T")
    let generic = LanguageModelProfile.load(folder: try folder(["system_prompt.txt": "G"]))
    #expect(generic.systemPrompt(for: .enhance, withImages: true) == "G")
    let onlyT = LanguageModelProfile.load(folder: try folder(["system_prompt_t2i.txt": "T"]))
    #expect(onlyT.systemPrompt(for: .enhance, withImages: true) == nil)
  }
}
