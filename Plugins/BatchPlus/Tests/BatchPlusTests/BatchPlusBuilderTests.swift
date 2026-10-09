import Foundation
import Testing

@testable import BatchPlus

@Suite("Batch plus builder")
struct BatchPlusBuilderTests {
  let base = BatchBase(
    steps: 10, guidanceScale: 3, shift: 3, cfgZeroInitSteps: 0, seed: 1234,
    loras: [BatchBase.LoRA(file: "x.ckpt", weight: 0.4), BatchBase.LoRA(file: "y.ckpt", weight: 1)])

  func steps(_ pipeline: [String: Any]) -> [[String: Any]] { pipeline["steps"] as? [[String: Any]] ?? [] }
  func fields(_ step: [String: Any]) -> [String: Any] { step["fields"] as? [String: Any] ?? [:] }

  @Test func severalIncrementsVaryTogether() {
    let batch = ParameterBatch(increments: [.steps: 10, .guidanceScale: 2], count: 3, fixedSeed: false)
    let pipeline = BatchPlusBuilder.pipeline(batch, from: base, italian: true)
    let list = steps(pipeline)
    #expect(list.count == 3)
    #expect(fields(list[0])["steps"] as? Int == 10 && fields(list[0])["guidanceScale"] as? Double == 3)
    #expect(fields(list[1])["steps"] as? Int == 20 && fields(list[1])["guidanceScale"] as? Double == 5)
    #expect(fields(list[2])["steps"] as? Int == 30 && fields(list[2])["guidanceScale"] as? Double == 7)
    #expect(list[1]["title"] as? String == "Passi 20 · Guidance 5")
    #expect(pipeline["name"] as? String == "Batch plus · Passi, Guidance")
  }

  @Test func aFixedSeedWithoutASeedIncrementIsTheCurrentSeedAndNeverRandom() {
    let batch = ParameterBatch(increments: [.steps: 5], count: 2, fixedSeed: true)
    for step in steps(BatchPlusBuilder.pipeline(batch, from: base, italian: false)) {
      #expect(fields(step)["seed"] as? Int == 1234)
      #expect(fields(step)["randomSeed"] as? Bool == false)
    }
  }

  @Test func aSeedIncrementMakesTheSeedGrowAndNeverRandom() {
    for fixed in [true, false] {
      let batch = ParameterBatch(increments: [.seed: 1], count: 3, fixedSeed: fixed)
      let seeds = steps(BatchPlusBuilder.pipeline(batch, from: base, italian: false)).map { fields($0)["seed"] as? Int }
      #expect(seeds == [1234, 1235, 1236])
      #expect(steps(BatchPlusBuilder.pipeline(batch, from: base, italian: false)).allSatisfy { fields($0)["randomSeed"] as? Bool == false })
    }
  }

  @Test func withoutAFixedSeedTheSeedIsLeftAlone() {
    let batch = ParameterBatch(increments: [.steps: 5], count: 2, fixedSeed: false)
    for step in steps(BatchPlusBuilder.pipeline(batch, from: base, italian: false)) {
      #expect(fields(step)["seed"] == nil && fields(step)["randomSeed"] == nil)
    }
  }

  @Test func loraWeightsGrowPerFile() {
    let batch = ParameterBatch(loraIncrements: ["x.ckpt": 0.2], count: 3, fixedSeed: false)
    let list = steps(BatchPlusBuilder.pipeline(batch, from: base, italian: false))
    let weights = list.map { ($0["loras"] as? [[String: Any]])?.first?["weight"] as? Double }
    #expect(weights == [0.4, 0.6, 0.8])
    #expect(list.allSatisfy { ($0["loras"] as? [[String: Any]])?.first?["file"] as? String == "x.ckpt" })
    #expect(list.allSatisfy { ($0["loras"] as? [[String: Any]])?.count == 1 })
    #expect(list[1]["title"] as? String == "x 0.6")
  }

  @Test func neverAPresetNorASize() {
    var batch = ParameterBatch(increments: [.steps: 5, .shift: 1, .cfgZeroInitSteps: 1], loraIncrements: ["y.ckpt": 0.1], count: 3)
    batch.fixedSeed = true
    for step in steps(BatchPlusBuilder.pipeline(batch, from: base, italian: false)) {
      #expect(step["preset"] == nil)
      #expect(fields(step)["width"] == nil && fields(step)["height"] == nil)
    }
    for step in steps(BatchPlusBuilder.pipeline(prompts: ["a", "b"], fixedSeed: true, seed: 5, italian: false)) {
      #expect(step["preset"] == nil && fields(step)["width"] == nil && fields(step)["height"] == nil)
    }
  }

  @Test func promptModeHasOnePassPerPrompt() {
    let pipeline = BatchPlusBuilder.pipeline(prompts: ["a cat", "a dog"], fixedSeed: true, seed: 77, italian: false)
    let list = steps(pipeline)
    #expect(pipeline["name"] as? String == "Batch plus · Prompts")
    #expect(list.map { $0["title"] as? String } == ["Prompt 1", "Prompt 2"])
    #expect(list.map { fields($0)["prompt"] as? String } == ["a cat", "a dog"])
    #expect(list.allSatisfy { fields($0)["seed"] as? Int == 77 && fields($0)["randomSeed"] as? Bool == false })
    let loose = steps(BatchPlusBuilder.pipeline(prompts: ["a"], fixedSeed: false, seed: 77, italian: false))
    #expect(fields(loose[0])["seed"] == nil && fields(loose[0])["randomSeed"] == nil)
  }

  @Test func theSeedIsKeptInItsRange() {
    var b = base
    b.seed = 4_294_967_295
    let batch = ParameterBatch(increments: [.seed: 5], count: 2)
    let seeds = steps(BatchPlusBuilder.pipeline(batch, from: b, italian: false)).map { fields($0)["seed"] as? Int }
    #expect(seeds == [4_294_967_295, 4_294_967_295])
  }

  @Test func thePreviewListsOnlyTheVaryingColumns() {
    let batch = ParameterBatch(increments: [.steps: 10], loraIncrements: ["x.ckpt": 0.2], count: 2)
    let rows = BatchPlusBuilder.preview(batch, from: base)
    #expect(rows == [["steps": 10, "lora:x.ckpt": 0.4], ["steps": 20, "lora:x.ckpt": 0.6]])
  }

  @Test func bothLanguagesHaveEveryWord() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "\(key) has no Italian")
      #expect(L.isDefined(key, italian: false), "\(key) has no English")
    }
  }
}
