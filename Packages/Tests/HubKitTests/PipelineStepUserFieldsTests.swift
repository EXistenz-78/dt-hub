import Foundation
import Testing

@testable import HubKit

struct PipelineStepUserFieldsTests {
  /// The three values of a user's pipeline are not part of the plug-ins' contract: a plug-in cannot set them.
  @Test func aStepFromJSONNeverHasTheUserPipelineFields() throws {
    let message = #"{"pipeline":{"steps":[{"title":"A","preset":"P","usesPresetModel":true,"scale":2,"strength":0.3}]}}"#
    let step = try #require(PluginContribution(message: Data(message.utf8))?.pipeline).steps[0]
    #expect(step.preset == "P")
    #expect(step.usesPresetModel == false)
    #expect(step.scale == 1)
    #expect(step.strength == nil)
  }

  @Test func aNewStepHasTheDefaults() {
    let step = PipelineStep(preset: "P")
    #expect(!step.usesPresetModel && step.scale == 1 && step.strength == nil)
  }
}
