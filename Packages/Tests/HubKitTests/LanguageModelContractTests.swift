import Foundation
import Testing

@testable import HubKit

struct LanguageModelContractTests {
  @Test func aModelIsIdentifiedByItsFolder() {
    let model = LanguageModelDescriptor(path: "/m/qwen", name: "qwen", sizeBytes: 10, supportsImages: false)
    #expect(model.id == "/m/qwen")
  }

  @Test func theRecommendedModelIsAHubRepositoryDownloadedIntoItsOwnFolder() {
    let parts = RecommendedLanguageModel.repository.split(separator: "/")
    #expect(parts.count == 2)
    #expect(RecommendedLanguageModel.folderName == RecommendedLanguageModel.repository)
    #expect(RecommendedLanguageModel.approximateBytes > 1_000_000_000)
  }

  func message(_ json: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
  }

  @Test func aMessageWithoutOptionsAsksWithTheDefaults() throws {
    #expect(LanguageModelOptions(message: try message(#"{"type":"llm","prompt":"hi"}"#)) == LanguageModelOptions())
  }

  @Test func theSystemPromptAndEveryOptionAreRead() throws {
    let options = LanguageModelOptions(
      message: try message(
        #"""
        {"type":"llm","prompt":"hi","system":"Answer in English.","options":
          {"temperature":1.0,"topP":0.95,"topK":20,"presencePenalty":1.5,"maxTokens":16256,"thinking":true}}
        """#))
    #expect(
      options
        == LanguageModelOptions(
          system: "Answer in English.", temperature: 1.0, topP: 0.95, topK: 20, presencePenalty: 1.5, maxTokens: 16256,
          thinking: true))
  }

  @Test func numbersOutOfRangeAreBroughtInAndWrongKindsAreLeftOut() throws {
    let options = LanguageModelOptions(
      message: try message(
        #"""
        {"system":"","options":{"temperature":9,"topP":-1,"topK":900,"presencePenalty":"high","maxTokens":0,
          "thinking":1,"unknown":true}}
        """#))
    #expect(options.system == nil)  // an empty system prompt is none
    #expect(options.temperature == 2)
    #expect(options.topP == 0)
    #expect(options.topK == 200)
    #expect(options.presencePenalty == nil)
    #expect(options.maxTokens == 1)
    #expect(options.thinking == nil)  // 1 is a number, not a boolean
  }

  @Test func thinkingCanBeSwitchedOffToo() throws {
    #expect(LanguageModelOptions(message: try message(#"{"options":{"thinking":false}}"#)).thinking == false)
  }

  @Test func everyErrorHasAReasonInPlainEnglishThatNamesWhatMatters() {
    #expect(LanguageModelError.modelNotFound("mlx/pe").plainText.contains("mlx/pe"))
    #expect(LanguageModelError.loadFailed("bad weights").plainText.contains("bad weights"))
    #expect(LanguageModelError.generationFailed("out of tokens").plainText.contains("out of tokens"))
    #expect(LanguageModelError.downloadFailed("offline").plainText == "offline")
    let all: [LanguageModelError] = [
      .noModelSelected, .notEnoughMemory(neededBytes: 5_000_000_000, availableBytes: 1_000_000_000), .imagesNotSupported,
      .interrupted,
    ]
    #expect(all.allSatisfy { !$0.plainText.isEmpty && !$0.plainText.contains("noModel") })
  }
}
