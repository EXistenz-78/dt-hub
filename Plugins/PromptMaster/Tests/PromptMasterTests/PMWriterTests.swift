import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMaster

/// What the writer asked of the app.
@MainActor
final class Recorder {
  struct Ask { var prompt: String; var system: String?; var model: String?; var options: DTHubLLMOptions }
  var asks: [Ask] = []
  var contributions: [[String: Any]] = []
  var answer: DTHubLLMAnswer = .text("A quiet harbour at dawn.")
  var accepted: [String: Any]? = ["type": "ok", "conflicts": 0]
}

@MainActor
@Suite("Writing the prompt")
struct PMWriterTests {
  private let masters = PMData.embeddedMasters

  private func writer(_ recorder: Recorder, files: [String: String] = [:], sizes: [String: Int64] = [:]) -> PMWriter {
    PMWriter(
      ask: { prompt, system, model, options in
        recorder.asks.append(.init(prompt: prompt, system: system, model: model, options: options))
        return recorder.answer
      },
      contribute: { recorder.contributions.append($0); return recorder.accepted },
      italian: false, folderSize: { sizes[$0] ?? 0 }, readFile: { files[$0.lastPathComponent] })
  }

  private func request(
    _ family: String = "flux2_9b", description: String = "un porto all'alba", terms: [SelectedTerm] = [],
    booru: Bool = false, models: [DTHubLanguageModel] = []
  ) -> PMWriter.Request {
    PMWriter.Request(
      family: family, masters: masters, description: description, terms: terms, booru: booru, languageModels: models)
  }

  private func term(_ english: String, avoid: Bool = false) -> SelectedTerm {
    SelectedTerm(id: english, title: english, categoryTitle: "C", english: english, isNegative: avoid)
  }

  private func model(_ name: String) -> DTHubLanguageModel {
    try! JSONDecoder().decode(
      DTHubLanguageModel.self, from: Data(#"{"name": "\#(name)", "path": "/models/\#(name)", "supportsImages": true}"#.utf8))
  }

  private func fields(_ recorder: Recorder) -> [String: Any]? { recorder.contributions.last?["fields"] as? [String: Any] }

  @Test func theFamilysMasterPromptIsTheSystemAndTheRequestHasDescriptionAndTerms() async {
    let recorder = Recorder()
    let outcome = await writer(recorder).write(request(terms: [term("Fog")]))
    let ask = recorder.asks[0]
    #expect(ask.system == masters.families["flux2_9b"]?.system)
    #expect(ask.prompt.contains("un porto all'alba") && ask.prompt.contains("- Fog"))
    #expect(ask.model == nil && ask.options == PMWriter.genericOptions)
    #expect(fields(recorder)?["prompt"] as? String == "A quiet harbour at dawn.")
    #expect(outcome.status == "Prompt sent to Generation." && outcome.sent)
  }

  @Test func theGenericModelIsToldNotToThinkForThePromptAndForTheScene() async {
    // A model that thinks by default would spend its tokens on the reasoning and never close it.
    let recorder = Recorder()
    _ = await writer(recorder).write(request())
    #expect(recorder.asks[0].options.thinking == false)
    _ = await writer(recorder).scene()
    #expect(recorder.asks[1].options.thinking == false)
  }

  @Test func theNegativePromptIsWrittenOnlyForAFamilyThatReadsOne() async {
    let recorder = Recorder()
    recorder.answer = .text(#"{"prompt": "a cat", "negative": "blurry"}"#)
    _ = await writer(recorder).write(request("sdxl_base_v0.9"))
    #expect(fields(recorder)?["prompt"] as? String == "a cat" && fields(recorder)?["negativePrompt"] as? String == "blurry")
    let flux = Recorder()
    flux.answer = .text(#"{"prompt": "a cat", "negative": "blurry"}"#)
    _ = await writer(flux).write(request("flux1"))
    #expect(fields(flux)?["prompt"] as? String == "a cat" && fields(flux)?["negativePrompt"] == nil)
  }

  @Test func theBooruSwitchReachesTheSystemPrompt() async {
    let recorder = Recorder()
    _ = await writer(recorder).write(request("v1", booru: true))
    #expect(recorder.asks[0].system?.hasSuffix(masters.families["v1"]!.booruSystem!) == true)
  }

  @Test func aFamilyWithoutAMasterPromptSendsNothing() async {
    let recorder = Recorder()
    let outcome = await writer(recorder).write(request("ideogram_4"))
    #expect(outcome.status == "This model has no master prompt." && !outcome.sent)
    #expect(recorder.asks.isEmpty && recorder.contributions.isEmpty)
  }

  @Test func whenTheLanguageModelFailsItsReasonIsShownAndNothingIsSent() async {
    let recorder = Recorder()
    recorder.answer = .failure("No language model is chosen.")
    let outcome = await writer(recorder).write(request())
    #expect(outcome.status == "No language model is chosen." && !outcome.sent)
    #expect(recorder.contributions.isEmpty)
  }

  @Test func anAnswerWithoutAPromptIsReportedAndNothingIsSent() async {
    let recorder = Recorder()
    recorder.answer = .text("<think>only thoughts")
    let outcome = await writer(recorder).write(request())
    #expect(outcome.status == "The language model's answer had no prompt in it." && recorder.contributions.isEmpty)
  }

  @Test func whatTheAppSaysAboutTheContributionIsShown() async {
    let recorder = Recorder()
    recorder.accepted = ["type": "ok", "conflicts": 2]
    #expect(await writer(recorder).write(request()).status == "Prompt sent. 2 conflict(s) waiting in the app.")
    recorder.accepted = ["type": "error", "text": "The plug-in is not active."]
    let refused = await writer(recorder).write(request())
    #expect(refused.status == "The plug-in is not active." && !refused.sent)
    recorder.accepted = nil
    #expect(await writer(recorder).write(request()).status == "No answer from the app.")
  }

  // MARK: Qwen Image 2.1

  private let t2i = "mlx/Qwen-Image-2.1-PE-T2I-MLX-4bit"
  private let i2i = "mlx/Qwen-Image-2.1-PE-I2I-MLX-4bit"
  private let files = ["system_prompt.txt": "T2I SYSTEM", "system_prompt_edit.txt": "EDIT SYSTEM"]

  @Test func theEnhancerGetsItsOwnSystemPromptTheRequestAndQwensSettings() async {
    let recorder = Recorder()
    recorder.answer = .text(#"<think>hm</think>{"rewritten_prompt": "a long rich prompt", "wh_ratio": "3:2"}"#)
    let outcome = await writer(recorder, files: files).write(
      request("qwen_image_2.1", terms: [term("Fog")], models: [model(t2i), model(i2i)]))
    let ask = recorder.asks[0]
    #expect(ask.model == t2i && ask.system == "T2I SYSTEM")
    #expect(ask.options.thinking == true && ask.options.maxTokens == 16256 && ask.options.timeout == 900)
    #expect(ask.prompt.contains("- Fog"))
    #expect(fields(recorder)?["prompt"] as? String == "a long rich prompt")
    #expect(fields(recorder)?["negativePrompt"] == nil)
    #expect(outcome.ratio == "3:2" && outcome.status == "Prompt sent to Generation. Suggested format: 3:2")
  }

  @Test func qwenImage21AlwaysGoesToTheTextToImageEnhancerAndNoPictureIsSent() async {
    let recorder = Recorder()
    _ = await writer(recorder, files: files).write(request("qwen_image_2.1", models: [model(t2i), model(i2i)]))
    #expect(recorder.asks[0].model == t2i && recorder.asks[0].system == "T2I SYSTEM")
  }

  @Test func withoutTheEnhancerTheGenericModelIsUsedAndTheLineSaysSoAndThatTheMasterPromptIsProvisional() async {
    let recorder = Recorder()
    let outcome = await writer(recorder).write(request("qwen_image_2.1"))
    #expect(recorder.asks[0].model == nil && recorder.asks[0].system == masters.families["qwen_image_2.1"]?.system)
    #expect(outcome.status.contains("Prompt enhancer not found") && outcome.status.contains("provisional"))
    let noSystem = Recorder()
    let second = await writer(noSystem, files: [:]).write(request("qwen_image_2.1", models: [model(t2i)]))
    #expect(second.status.contains("has no system_prompt.txt") && noSystem.asks[0].model == nil)
  }

  @Test func aFailureOfTheEnhancerIsShownAndDoesNotFallBackInSilence() async {
    let recorder = Recorder()
    recorder.answer = .failure("The language model needs about 6 GB and only 2 GB is free.")
    let outcome = await writer(recorder, files: files).write(request("qwen_image_2.1", models: [model(t2i)]))
    #expect(outcome.status.contains("only 2 GB is free") && !outcome.sent && recorder.asks.count == 1)
  }

  // MARK: The scene

  @Test func theSceneComesBackAsTextInTheInterfaceLanguage() async throws {
    let recorder = Recorder()
    recorder.answer = .text("A fisherman mends a net. A foggy pier at dawn.")
    #expect(try await writer(recorder).scene().get() == "A fisherman mends a net. A foggy pier at dawn.")
    #expect(recorder.asks[0].prompt.contains("English") && recorder.asks[0].system == PMWriter.sceneSystem)
    #expect(recorder.contributions.isEmpty)  // the scene goes in the description, not to Generation
  }

  @Test func aFailedSceneSaysWhy() async {
    let recorder = Recorder()
    recorder.answer = .failure("No language model is chosen.")
    #expect(await writer(recorder).scene() == .failure(.init(text: "No scene: No language model is chosen.")))
  }

  @Test func bothLanguagesHaveEveryWord() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true) && L.isDefined(key, italian: false), "\(key)")
    }
    // The placeholders match in the two languages.
    for key in L.Key.allCases {
      let count = { (text: String) in text.components(separatedBy: "%").count }
      #expect(count(L.text(key, italian: true)) == count(L.text(key, italian: false)), "\(key)")
    }
  }
}
