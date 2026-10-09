import Foundation
import Testing

@testable import DTHubPluginKit

@Suite("DTHubPluginKit")
struct DTHubPluginKitTests {
  @Test func theContractVersionIsStillOne() {
    #expect(DTHubContract.current == 1)
  }

  @Test func aBareMessageIsAnObjectWithItsType() {
    #expect(DTHubMessage.type(of: DTHubMessage.bare("ok")) == "ok")
  }

  @Test func aQuestionWithoutTheNewKeysIsTheOldMessage() throws {
    let message = DTHubHost.llmMessage(prompt: "hi", images: [], system: nil, model: nil, options: DTHubLLMOptions())
    #expect(Set(message.keys) == ["type", "prompt", "images"])
    #expect(DTHubHost.llmMessage(prompt: "hi", images: [], system: "", model: "", options: DTHubLLMOptions()).count == 3)
  }

  @Test func theSystemPromptTheModelAndTheOptionsGoInTheMessage() throws {
    let options = DTHubLLMOptions(temperature: 1, topK: 20, maxTokens: 100, thinking: false, timeout: 900)
    let message = DTHubHost.llmMessage(
      prompt: "hi", images: ["/a.png"], system: "Be brief.", model: "mlx/pe", options: options)
    #expect(message["system"] as? String == "Be brief.")
    #expect(message["model"] as? String == "mlx/pe")
    let sent = try #require(message["options"] as? [String: Any])
    #expect(sent["temperature"] as? Double == 1)
    #expect(sent["topK"] as? Int == 20)
    #expect(sent["maxTokens"] as? Int == 100)
    #expect(sent["thinking"] as? Bool == false)
    #expect(sent["timeout"] == nil)  // the wait is this library's business
    #expect(sent["topP"] == nil)
  }

  @Test func theWaitIsFiveMinutesUnlessAskedAndNeverMoreThanHalfAnHour() {
    #expect(DTHubLLMOptions().effectiveTimeout == 300)
    #expect(DTHubLLMOptions(timeout: 900).effectiveTimeout == 900)
    #expect(DTHubLLMOptions(timeout: 99_999).effectiveTimeout == 1800)
    #expect(DTHubLLMOptions(timeout: 0).effectiveTimeout == 1)
  }

  @Test func theContextReadsTheStartImageTheMoodboardAndTheModelsWhenTheyAreThereAndNotWhenTheyAreNot() throws {
    let full = try JSONDecoder().decode(
      DTHubContext.self,
      from: Data(
        #"""
        {"type":"context","tempFolder":"/t","startImage":"/s.png","moodboard":["/m1.png","/m2.png"],
         "languageModels":[{"name":"a/b","path":"/m/a/b","supportsImages":true}]}
        """#.utf8))
    #expect(full.startImage == "/s.png")
    #expect(full.moodboard == ["/m1.png", "/m2.png"])
    #expect(full.languageModels == [DTHubLanguageModel(name: "a/b", path: "/m/a/b", supportsImages: true)])
    let old = try JSONDecoder().decode(DTHubContext.self, from: Data(#"{"type":"context","tempFolder":"/t"}"#.utf8))
    #expect(old.startImage == nil && old.moodboard == nil && old.languageModels == nil)
  }
}

@Suite("DTHubProject")
struct DTHubProjectTests {
  @Test func decodesTheMessageOfTheApp() throws {
    let json = #"{"type":"project","name":"Campagna","folder":"/x/.dthub/plugins/a","adoptLegacy":true}"#
    let project = try JSONDecoder().decode(DTHubProject.self, from: Data(json.utf8))
    #expect(project.name == "Campagna")
    #expect(project.folder == "/x/.dthub/plugins/a")
    #expect(project.adoptLegacy)
  }

  @Test func adoptLegacyIsFalseWhenAbsent() throws {
    let json = #"{"type":"project","name":"A","folder":"/f"}"#
    #expect(try JSONDecoder().decode(DTHubProject.self, from: Data(json.utf8)).adoptLegacy == false)
  }

  @Test func aLanguageModelCarriesItsFamilyAndUseWhenTheAppSaysSo() throws {
    let json = #"{"type":"context","tempFolder":"/t","languageModels":[{"name":"pe","path":"/m/pe","supportsImages":false,"family":"qwen_image_2.1","use":"enhance"},{"name":"old","path":"/m/old","supportsImages":true}]}"#
    let context = try JSONDecoder().decode(DTHubContext.self, from: Data(json.utf8))
    #expect(context.languageModels?[0].family == "qwen_image_2.1" && context.languageModels?[0].use == "enhance")
    #expect(context.languageModels?[1].family == nil && context.languageModels?[1].use == nil)
  }

  /// The JSON the app really sends: a `PluginContext` with every kind of value.
  private let contextJSON = #"""
    {"type":"context","tempFolder":"/t","model":"m.ckpt","family":"flux2_9b",
     "parameters":{"width":832,"height":1216,"steps":8,"guidanceScale":1.5,"sampler":17,"seed":4294967295,
       "randomSeed":false,"resolutionDependentShift":true,"shift":3,"batchSize":1,"batchCount":2,
       "loras":[{"file":"x.ckpt","weight":0.6,"mode":0,"trigger":"zzz"}],
       "advanced":{"clipSkip":2,"hiresFix":true,"refinerModel":"","list":[1,2]},
       "extra":{"foo":"bar","n":1.5}}}
    """#

  @Test func theParametersOfTheTabArriveInTheContext() throws {
    let context = try JSONDecoder().decode(DTHubContext.self, from: Data(contextJSON.utf8))
    let p = try #require(context.parameters)
    #expect(p.steps == 8 && p.width == 832 && p.height == 1216 && p.guidanceScale == 1.5 && p.sampler == 17)
    #expect(p.seed == 4_294_967_295 && p.randomSeed == false && p.batchCount == 2)
    #expect(p.loras == [DTHubLoRA(file: "x.ckpt", weight: 0.6, mode: 0, trigger: "zzz")])
    #expect(p.advanced?["clipSkip"] == .number(2) && p.advanced?["hiresFix"] == .bool(true))
    #expect(p.advanced?["refinerModel"] == .string("") && p.advanced?["list"] == DTHubValue.other)
    #expect(p.extra?["foo"] == .string("bar"))
    #expect(context.model == "m.ckpt" && context.family == "flux2_9b")
  }

  @Test func aContextWithoutParametersStillDecodes() throws {
    let context = try JSONDecoder().decode(DTHubContext.self, from: Data(#"{"type":"context","tempFolder":"/t"}"#.utf8))
    #expect(context.parameters == nil && context.tempFolder == "/t")
  }

  @Test func wrongTypesInParametersCostOnlyThatValue() throws {
    let json = #"{"type":"context","tempFolder":"/t","model":"m","parameters":{"steps":"twenty","width":512,"loras":"none"}}"#
    let context = try JSONDecoder().decode(DTHubContext.self, from: Data(json.utf8))
    #expect(context.parameters?.steps == nil && context.parameters?.width == 512 && context.parameters?.loras == nil)
    #expect(context.model == "m")
    let wholeWrong = try JSONDecoder().decode(
      DTHubContext.self, from: Data(#"{"type":"context","tempFolder":"/t","model":"m","parameters":"oops"}"#.utf8))
    #expect(wholeWrong.parameters == nil && wholeWrong.model == "m" && wholeWrong.tempFolder == "/t")
  }
}
