import Foundation
import Testing

@testable import HubKit

struct GenerationParametersTests {
  @Test func clampsIntoTheAllowedRanges() {
    let wild = GenerationParameters(
      width: 10, height: 9999, steps: 500, guidanceScale: -1, shift: 20, batchSize: 0, batchCount: 1000)
    let clamped = wild.clamped()
    #expect(clamped.width == 64)
    #expect(clamped.height == 2048)
    #expect(clamped.steps == 150)
    #expect(clamped.guidanceScale == 0)
    #expect(clamped.shift == 10)
    #expect(clamped.batchSize == 1)
    #expect(clamped.batchCount == 100)
  }

  @Test func roundsSizesToTheNearestMultipleOf64() {
    let clamped = GenerationParameters(width: 1000, height: 1343).clamped()
    #expect(clamped.width == 1024)
    #expect(clamped.height == 1344)
  }

  @Test func samplersMatchDrawThingsRawValues() {
    #expect(Sampler.allCases.count == 20)
    #expect(Sampler.dpmpp2mKarras.rawValue == 0)
    #expect(Sampler.tcdTrailing.rawValue == 19)
  }

  @Test func swapsWidthAndHeight() {
    var parameters = GenerationParameters(width: 832, height: 1216)
    parameters.swapDimensions()
    #expect(parameters.width == 1216)
    #expect(parameters.height == 832)
  }

  @Test func cfgZeroInitStepsNeverExceedTheSteps() {
    let clamped = GenerationParameters(steps: 8, cfgZeroStar: true, cfgZeroInitSteps: 20).clamped()
    #expect(clamped.cfgZeroInitSteps == 8)
  }

  @Test func resolutionDependentShiftIsOnByDefault() {
    #expect(GenerationParameters.default.resolutionDependentShift)
    #expect(!GenerationParameters.default.cfgZeroStar)
  }
}

struct LoRASelectionTests {
  @Test func addsALoRAOnceAtFullWeight() {
    var parameters = GenerationParameters.default
    parameters.addLoRA("style.safetensors")
    parameters.loras[0].weight = 0.6
    parameters.addLoRA("style.safetensors")
    #expect(parameters.loras == [LoRASelection(file: "style.safetensors", weight: 0.6)])
  }

  @Test func addsALoRAWithItsSuggestedWeightAndTrigger() {
    var parameters = GenerationParameters.default
    parameters.addLoRA("tarot.safetensors", weight: 0.8, trigger: "vintage tarot style")
    #expect(parameters.loras == [LoRASelection(file: "tarot.safetensors", weight: 0.8, trigger: "vintage tarot style")])
  }

  @Test func triggerWordsGoInFrontOfThePromptInOrder() {
    let job = GenerationJob(
      prompt: "a fox in the snow", model: "m.ckpt",
      parameters: GenerationParameters(loras: [
        LoRASelection(file: "a", trigger: "70sfairytale, "), LoRASelection(file: "b"),
        LoRASelection(file: "c", trigger: " cine1p "),
      ]))
    #expect(job.promptWithTriggers == "70sfairytale, cine1p a fox in the snow")
    #expect(job.prompt == "a fox in the snow")
  }

  @Test func withoutTriggersThePromptIsSentAsItIs() {
    let job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: .default)
    #expect(job.promptWithTriggers == "a fox")
  }

  @Test func updatesTheLoRAWithThatFileWhereverItIs() {
    var parameters = GenerationParameters(loras: [LoRASelection(file: "a"), LoRASelection(file: "b")])
    parameters.updateLoRA(LoRASelection(file: "b", weight: 0.3, trigger: "x"))
    #expect(parameters.loras == [LoRASelection(file: "a"), LoRASelection(file: "b", weight: 0.3, trigger: "x")])
  }

  @Test func updatingALoRAAlreadyRemovedChangesNothing() {
    var parameters = GenerationParameters(loras: [LoRASelection(file: "a"), LoRASelection(file: "b")])
    parameters.removeLoRA("b")
    // A row still editing "b" ends its edit after the removal.
    parameters.updateLoRA(LoRASelection(file: "b", weight: 0.3))
    #expect(parameters.loras == [LoRASelection(file: "a")])
  }

  @Test func thePromptIsTrimmedWhereItJoinsTheTriggers() {
    let job = GenerationJob(
      prompt: "\n  a fox  ", model: "m.ckpt", parameters: GenerationParameters(loras: [LoRASelection(file: "a", trigger: "cine1p")]))
    #expect(job.promptWithTriggers == "cine1p a fox")
    let blank = GenerationJob(prompt: "   ", model: "m.ckpt", parameters: GenerationParameters(loras: [LoRASelection(file: "a", trigger: "cine1p")]))
    #expect(blank.promptWithTriggers == "cine1p")
  }

  @Test func removesALoRA() {
    var parameters = GenerationParameters(loras: [LoRASelection(file: "a"), LoRASelection(file: "b")])
    parameters.removeLoRA("a")
    #expect(parameters.loras.map(\.file) == ["b"])
  }

  @Test func clampsLoRAWeights() {
    let clamped = GenerationParameters(loras: [LoRASelection(file: "a", weight: 9), LoRASelection(file: "b", weight: -3)]).clamped()
    #expect(clamped.loras.map(\.weight) == [2.5, -1.5])
  }

  @Test func loRAModesMatchDrawThingsRawValues() {
    #expect(LoRAMode.all.rawValue == 0)
    #expect(LoRAMode.base.rawValue == 1)
    #expect(LoRAMode.refiner.rawValue == 2)
  }
}

struct LenientDecodingTests {
  @Test func missingFieldsTakeTheirDefaults() throws {
    let decoded = try JSONDecoder().decode(GenerationParameters.self, from: Data(#"{"width": 768, "steps": 30}"#.utf8))
    var expected = GenerationParameters.default
    expected.width = 768
    expected.steps = 30
    #expect(decoded == expected)
  }

  @Test func unreadableFieldsTakeTheirDefaults() throws {
    let decoded = try JSONDecoder().decode(GenerationParameters.self, from: Data(#"{"sampler": 99, "height": "tall"}"#.utf8))
    #expect(decoded.sampler == GenerationParameters.default.sampler)
    #expect(decoded.height == GenerationParameters.default.height)
  }

  @Test func parametersSurviveARoundTrip() throws {
    let parameters = GenerationParameters(width: 832, seed: 5, randomSeed: false, loras: [LoRASelection(file: "a", weight: 0.5, mode: .base)])
    let decoded = try JSONDecoder().decode(GenerationParameters.self, from: JSONEncoder().encode(parameters))
    #expect(decoded == parameters)
  }

  @Test func aLoRAWithoutTriggerOrModeLoads() throws {
    let decoded = try JSONDecoder().decode(LoRASelection.self, from: Data(#"{"file": "a", "weight": 0.5}"#.utf8))
    #expect(decoded == LoRASelection(file: "a", weight: 0.5))
  }

  @Test func aJobWithoutANegativePromptLoads() throws {
    let json = #"{"prompt": "fox", "model": "m.ckpt", "parameters": {}}"#
    let job = try JSONDecoder().decode(GenerationJob.self, from: Data(json.utf8))
    #expect(job.negativePrompt == "")
    #expect(job.parameters == .default)
  }
}
