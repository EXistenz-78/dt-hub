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

  // MARK: Guided pipelines

  private func unusualObject() -> [String: Any] {
    [
      "quote": "a\"b", "text": "è ñ 日本", "list": [1, 2.5, true, NSNull()],
      "big": 123_456_789_012_345, "nested": ["k": ["deep": "v"]],
    ]
  }

  @Test func snapshotRoundTripsUnusualText() throws {
    let snapshot = try #require(QueueSnapshot(jsonObject: unusualObject()))
    let back = try JSONDecoder().decode(QueueSnapshot.self, from: JSONEncoder().encode(snapshot))
    #expect(back == snapshot)
    let object = back.jsonObject
    #expect(object["quote"] as? String == "a\"b")
    #expect(object["text"] as? String == "è ñ 日本")
    #expect((object["big"] as? NSNumber)?.int64Value == 123_456_789_012_345)
    #expect(((object["nested"] as? [String: Any])?["k"] as? [String: Any])?["deep"] as? String == "v")
    #expect((object["list"] as? [Any])?.count == 4)
  }

  @Test func snapshotRejectsWhatIsNotJSON() {
    #expect(QueueSnapshot(jsonObject: ["x": Date()]) == nil)
  }

  @Test func guidedPipelineRoundTrips() throws {
    let state = try #require(QueueSnapshot(jsonObject: unusualObject()))
    let entry = QueueEntry(
      preset: preset(), pipeline: .guided(pluginID: "tiled-upscale", name: "Tiled Upscale", passes: 9, state: state))
    #expect(try roundTrip(entry) == entry)
  }

  @Test func unknownPipelineKindKeepsTheEntry() throws {
    let json = #"{"id":"\#(UUID().uuidString)","preset":{"prompt":"x"},"pipeline":{"future":{}}}"#
    let entry = try JSONDecoder().decode(QueueEntry.self, from: Data(json.utf8))
    #expect(entry.pipeline == nil)
    #expect(entry.preset.prompt == "x")
  }
}
