import Foundation
import Testing

@testable import HubKit

struct PipelineStepCodingTests {
  private func roundTrip(_ step: PipelineStep) throws -> PipelineStep {
    try JSONDecoder().decode(PipelineStep.self, from: JSONEncoder().encode(step))
  }

  @Test func roundTripOfASphereLightStep() throws {
    let step = PipelineStep(
      title: "Match the sun", preset: "Sphere Match",
      fields: FieldOverlay([
        .steps: .int(8), .guidanceScale: .double(1.5), .prompt: .text("sun"), .randomSeed: .bool(true),
      ]),
      moodboard: [PluginImageRef(name: "sphere.png", path: "/tmp/sphere.png")], useOutputAsStart: true)
    #expect(try roundTrip(step) == step)
  }

  @Test func roundTripKeepsEveryOptionalField() throws {
    let step = PipelineStep(
      title: "t", preset: "p", startImage: PluginImageRef(name: "s.png", path: "/tmp/s.png"),
      usesPresetModel: true, scale: 1.5, strength: 0.4,
      mask: PluginImageRef(name: "m.png", path: "/tmp/m.png"), maskSettings: MaskSettings(),
      size: PipelineSize(width: 1024, height: 768))
    #expect(try roundTrip(step) == step)
  }

  @Test func missingKeysDecodeToDefaults() throws {
    let step = try JSONDecoder().decode(PipelineStep.self, from: Data("{}".utf8))
    #expect(step == PipelineStep())
  }

  @Test func anUnknownFieldKeyIsIgnored() throws {
    let json = #"{"fields": {"nonsense": 3, "steps": 4}}"#
    let step = try JSONDecoder().decode(PipelineStep.self, from: Data(json.utf8))
    #expect(step.fields == FieldOverlay([.steps: .int(4)]))
  }
}
