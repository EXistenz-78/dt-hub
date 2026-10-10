import DTHubPluginKit
import Foundation
import Testing

@testable import AIAssistant

@Suite("History, images and system prompt")
struct HistoryAndPromptTests {
  func msg(_ role: ChatMessage.Role, _ text: String) -> ChatMessage { ChatMessage(role: role, text: text) }

  @Test func theNotesAreLeftOutAndTheRolesAreRight() {
    let result = HistoryWindow.turns(of: [msg(.user, "a"), msg(.note, "Sent"), msg(.assistant, "b"), msg(.user, "c")])
    #expect(result.turns == [
      DTHubLLMTurn(role: .user, text: "a"), DTHubLLMTurn(role: .assistant, text: "b"), DTHubLLMTurn(role: .user, text: "c"),
    ])
    #expect(!result.trimmed)
  }

  @Test func onlyTheMostRecentMessagesThatFitAreKept() {
    let big = String(repeating: "x", count: 10_000)
    let messages = [msg(.user, big), msg(.assistant, big), msg(.user, big), msg(.assistant, big)]
    let result = HistoryWindow.turns(of: messages, budget: 24_000)
    #expect(result.turns.count == 2 && result.trimmed)
    #expect(result.turns[0].role == .user && result.turns[1].role == .assistant)
  }

  @Test func aSingleMessageLongerThanTheBudgetGivesNoTurns() {
    let result = HistoryWindow.turns(of: [msg(.user, String(repeating: "x", count: 30_000))], budget: 24_000)
    #expect(result.turns.isEmpty && result.trimmed)
  }

  @Test func theImageBlockIsNumberedAsDrawThingsDoes() {
    let block = ImageLabels.block(hasStart: true, references: 2)
    #expect(
      block == "Attached images:\n- Image 1: the start image (the picture being edited).\n- Image 2: reference image 1.\n- Image 3: reference image 2.\n\nThe prompt refers to these images. Look at them to make the description concrete and accurate, and keep every reference to an image (image 1, image 2…) exactly as written.\n\n")
    #expect(ImageLabels.block(hasStart: false, references: 1)?.contains("- Image 1: reference image 1.") == true)
    #expect(ImageLabels.block(hasStart: false, references: 0) == nil)
  }

  func context(_ json: String) throws -> DTHubContext {
    try JSONDecoder().decode(DTHubContext.self, from: Data(json.utf8))
  }

  @Test func theSystemPromptCarriesTheStateOfTheTab() throws {
    let json = #"""
      {"type":"context","tempFolder":"/t","model":"flux.ckpt","family":"flux2_9b","prompt":"a cat","negativePrompt":"blur","strength":0.7,"startImage":"/s.png","moodboard":["/m.png"],
       "parameters":{"width":832,"height":1216,"steps":8,"guidanceScale":1.5,"sampler":0,"shift":3,"resolutionDependentShift":true,"seed":99,"randomSeed":true,"cfgZeroStar":false,"cfgZeroInitSteps":0,"batchSize":1,"batchCount":2,
       "loras":[{"file":"x.ckpt","weight":0.6,"mode":0,"trigger":""}]}}
      """#
    let text = SystemPrompt.make(context: try context(json))
    #expect(text.contains(#"Prompt: """a cat""""#) && text.contains(#"Negative prompt: """blur""""#))
    #expect(text.contains("Sampler: DPM++ 2M Karras"))
    #expect(text.contains("Start image: yes, strength 0.70") && text.contains("Moodboard pictures on: 1"))
    #expect(text.contains("x.ckpt (weight 0.6)") && text.contains("832 × 1216") && text.contains("(automatic, ignored)"))
    #expect(text.contains("Seed: 99 (random)") && text.contains("Batch: 1 × 2"))
    #expect(text.contains("<DO IT>") && text.contains("<FALLO>") && text.contains("At most 20 steps"))
    #expect(text.contains("DDIM") && text.contains("UniPC Trailing"))
  }

  @Test func withoutParametersTheValuesAreUnknown() throws {
    let text = SystemPrompt.make(context: try context(#"{"type":"context","tempFolder":"/t"}"#))
    #expect(text.contains("Model: unknown (family: unknown)") && text.contains("Size: unknown") && text.contains("LoRAs: unknown"))
    #expect(text.contains("Start image: none"))
  }

  @Test func theFamilyGuideOfTheAppIsInThePromptWhenThereIsOne() throws {
    let json = #"{"type":"context","tempFolder":"/t","model":"m","family":"flux2_9b","promptGuide":{"label":"FLUX.2 [klein] 9B","usesNegative":false,"notes":"- Write in plain prose."}}"#
    let with = SystemPrompt.make(context: try context(json))
    #expect(with.contains("PROMPT GUIDE FOR FLUX.2 [klein] 9B"))
    #expect(with.contains("does not use a negative prompt") && with.contains("- Write in plain prose."))
    #expect(with.range(of: "PROMPT GUIDE")!.lowerBound < with.range(of: "ACTIONS")!.lowerBound)
    let without = SystemPrompt.make(context: try context(#"{"type":"context","tempFolder":"/t"}"#))
    #expect(!without.contains("PROMPT GUIDE"))
  }
}
