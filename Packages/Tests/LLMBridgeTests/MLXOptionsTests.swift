import HubKit
import Testing

@testable import LLMBridge

struct MLXOptionsTests {
  @Test func withoutOptionsTheOldDefaultsHold() {
    let parameters = MLXLanguageModelService.generateParameters(for: LanguageModelOptions())
    #expect(parameters.maxTokens == 1024)
    #expect(parameters.temperature == 0.6)
    #expect(parameters.topP == 1)
    #expect(parameters.topK == 0)
    #expect(parameters.presencePenalty == nil)
    #expect(MLXLanguageModelService.templateContext(for: LanguageModelOptions()) == nil)
  }

  @Test func theOptionsBecomeGenerationParameters() {
    let parameters = MLXLanguageModelService.generateParameters(
      for: LanguageModelOptions(temperature: 1, topP: 0.95, topK: 20, presencePenalty: 1.5, maxTokens: 16256))
    #expect(parameters.maxTokens == 16256)
    #expect(parameters.temperature == 1)
    #expect(parameters.topP == 0.95)
    #expect(parameters.topK == 20)
    #expect(parameters.presencePenalty == 1.5)
  }

  @Test func thinkingReachesTheChatTemplateOnlyWhenSaid() {
    #expect(MLXLanguageModelService.templateContext(for: LanguageModelOptions(thinking: true))?["enable_thinking"] as? Bool == true)
    #expect(MLXLanguageModelService.templateContext(for: LanguageModelOptions(thinking: false))?["enable_thinking"] as? Bool == false)
  }
}
