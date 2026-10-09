import Foundation
import Testing

@testable import HubKit

struct PipelineStepTests {
  func steps(_ json: String) throws -> [PipelineStep] {
    let message = #"{"pipeline":{"steps":[\#(json)]}}"#
    return try #require(PluginContribution(message: Data(message.utf8))?.pipeline).steps
  }

  @Test func aStepCarriesJustTheValuesToChange() throws {
    let step = try steps(
      #"{"title":"A","fields":{"steps":20,"guidanceScale":5.5},"loras":[{"file":"x.ckpt","weight":0.6}]}"#)[0]
    #expect(step.fields.fields == [.steps, .guidanceScale])
    #expect(step.preset.isEmpty)
    #expect(step.loras == [LoRASelection(file: "x.ckpt", weight: 0.6)])
  }

  @Test func anOldPresetOnlyStepReadsAsBefore() throws {
    let step = try steps(#"{"title":"B","preset":"SLR · Overcast"}"#)[0]
    #expect(step.preset == "SLR · Overcast")
    #expect(step.fields.isEmpty && step.loras.isEmpty)
  }

  @Test func unknownKeysAreIgnoredAndValuesAreLimitedWhenApplied() throws {
    let step = try steps(#"{"fields":{"nonsense":1,"steps":9999},"loras":[{"file":"y.ckpt","weight":99}]}"#)[0]
    #expect(step.fields.fields == [.steps])
    let applied = step.fields.applied(to: GenerationFields())
    #expect(applied.parameters.steps < 9999)
    #expect(step.loras.first?.weight == LoRASelection.weightRange.upperBound)
  }
}
