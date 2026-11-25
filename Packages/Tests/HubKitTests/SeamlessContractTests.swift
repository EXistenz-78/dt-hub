import Foundation
import Testing

@testable import HubKit

struct SeamlessContractTests {
  @Test func theConfigurationValuesAreTheServersOnes() {
    #expect(SeamlessTile.leftRight.configurationValue == 1)
    #expect(SeamlessTile.upDown.configurationValue == 2)
    #expect(SeamlessTile.both.configurationValue == 3)
    #expect(SeamlessTile.families == ["krea_2", "z_image", "flux2_9b", "flux2_4b", "flux3_5b"])
  }

  @Test func theProblemTextsAreExact() {
    #expect(SeamlessTile.problem(customServer: false, family: "krea_2") == "seamless: the custom server is not running.")
    #expect(SeamlessTile.problem(customServer: true, family: "sdxl") == "seamless: this model family does not support it.")
    #expect(SeamlessTile.problem(customServer: true, family: nil) == "seamless: this model family does not support it.")
    #expect(SeamlessTile.problem(customServer: true, family: "flux3_5b") == nil)
  }

  @Test func aPipelineStepReadsSeamless() throws {
    func step(_ json: String) throws -> PipelineStep? {
      try #require(PluginContribution(message: Data(json.utf8))).pipeline?.steps.first
    }
    #expect(try step(#"{"pipeline":{"steps":[{"seamless":"both"}]}}"#)?.seamless == .both)
    #expect(try step(#"{"pipeline":{"steps":[{"seamless":"leftRight"}]}}"#)?.seamless == .leftRight)
    #expect(try step(#"{"pipeline":{"steps":[{"seamless":"upDown"}]}}"#)?.seamless == .upDown)
    #expect(try step(#"{"pipeline":{"steps":[{"seamless":"diagonal"}]}}"#)?.seamless == nil)
    #expect(try step(#"{"pipeline":{"steps":[{"title":"x"}]}}"#)?.seamless == nil)
  }

  @Test func aQueuedStepKeepsSeamless() throws {
    let step = PipelineStep(title: "t", seamless: .both)
    let copy = try JSONDecoder().decode(PipelineStep.self, from: JSONEncoder().encode(step))
    #expect(copy.seamless == .both)
    #expect(copy == step)
    // Without it the saved step has no key (an old queue file reads the same).
    let plain = try JSONEncoder().encode(PipelineStep(title: "t"))
    #expect(!String(decoding: plain, as: UTF8.self).contains("seamless"))
  }

  @Test func aNullPipelineWithdrawsItAndAnAbsentOneDoesNot() throws {
    let withdraw = try #require(PluginContribution(message: Data(#"{"type":"contribute","pipeline":null}"#.utf8)))
    #expect(withdraw.withdrawsPipeline)
    #expect(withdraw.pipeline == nil)
    #expect(!withdraw.isEmpty)
    let none = try #require(PluginContribution(message: Data(#"{"type":"contribute","fields":{"steps":4}}"#.utf8)))
    #expect(!none.withdrawsPipeline)
  }

  @Test func aJobCarriesSeamlessOnlyWhenSet() throws {
    var job = GenerationJob(prompt: "p", model: "m", parameters: GenerationParameters())
    #expect(job.seamlessTile == nil)
    #expect(!String(decoding: try JSONEncoder().encode(job), as: UTF8.self).contains("seamlessTile"))
    job.seamlessTile = .upDown
    let copy = try JSONDecoder().decode(GenerationJob.self, from: JSONEncoder().encode(job))
    #expect(copy.seamlessTile == .upDown)
  }

  @Test func theContextSaysWhetherTheServerIsCustom() throws {
    for flag in [true, false] {
      var context = PluginContext(model: nil, family: nil, parameters: GenerationParameters(), tempFolder: "/t")
      context.customServer = flag
      let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any])
      #expect(object["customServer"] as? Bool == flag)
    }
    let older = PluginContext(model: nil, family: nil, parameters: GenerationParameters(), tempFolder: "/t")
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(older)) as? [String: Any])
    #expect(object["customServer"] == nil)
  }
}
