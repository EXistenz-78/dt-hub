import Foundation
import Testing

@testable import HubKit

struct QueueEntryTests {
  private func roundTrip(_ entry: QueueEntry) throws -> QueueEntry {
    try JSONDecoder().decode(QueueEntry.self, from: JSONEncoder().encode(entry))
  }

  private func preset() -> Preset {
    var parameters = GenerationParameters.default
    parameters.width = 832
    parameters.height = 1216
    return Preset(name: "", model: "flux.ckpt", prompt: "a cat", negativePrompt: "blurry", parameters: parameters)
  }

  @Test func roundTripOfAFullEntry() throws {
    var control = ControlInputs()
    control.framing.zoom = 1.5
    let entry = QueueEntry(
      status: .failed("modello assente"), preset: preset(), lockRatio: true, control: control,
      pipeline: .plugin(pluginID: "sphere", name: "Sphere Light", steps: [PipelineStep(title: "a", preset: "p")]))
    #expect(try roundTrip(entry) == entry)
  }

  @Test func userPipelineRoundTrip() throws {
    let entry = QueueEntry(preset: preset(), pipeline: .user(name: "Upscale 2x"))
    #expect(try roundTrip(entry).pipeline == .user(name: "Upscale 2x"))
  }

  @Test func aMissingStatusDecodesAsPending() throws {
    let json = #"{"id":"\#(UUID().uuidString)","preset":{"prompt":"x"}}"#
    let entry = try JSONDecoder().decode(QueueEntry.self, from: Data(json.utf8))
    #expect(entry.status == .pending)
    #expect(entry.pipeline == nil)
    #expect(entry.preset.prompt == "x")
  }

  @Test func thePresetKeepsItsSize() throws {
    let back = try roundTrip(QueueEntry(preset: preset()))
    #expect(back.preset.parameters.width == 832)
    #expect(back.preset.parameters.height == 1216)
  }

  @Test func aMissingPipelineIsNil() throws {
    #expect(try roundTrip(QueueEntry(preset: preset())).pipeline == nil)
  }
}
