import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct ContributionReviewTests {
  func result() -> GeneratedImage {
    let context = CGContext(
      data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return GeneratedImage(
      image: context.makeImage()!, job: GenerationJob(prompt: "", model: "m", parameters: GenerationParameters()),
      date: Date(), fileURL: nil, saveError: nil)
  }

  @Test func onlyAResultThatArrivedAfterThePassCountsAsItsOutput() {
    let old = result()
    let new = result()
    #expect(PipelineInputs.output(after: old.id, in: [old]) == nil)
    #expect(PipelineInputs.output(after: old.id, in: [new, old])?.id == new.id)
    #expect(PipelineInputs.output(after: nil, in: [old])?.id == old.id)
    #expect(PipelineInputs.output(after: nil, in: []) == nil)
  }

  @Test func aPassThatReplacesTheStartImageIgnoresTheTabsMaskAndMargins() {
    let masked = ControlInputs(mask: MaskReference(fileName: "m.png", coverage: 0.3))
    #expect(PipelineInputs.strength(tab: masked, replacesStart: false, editModel: false, hasMargins: false) == 1.0)
    #expect(PipelineInputs.strength(tab: masked, replacesStart: true, editModel: false, hasMargins: true) == 0.7)
    #expect(PipelineInputs.strength(tab: masked, replacesStart: true, editModel: true, hasMargins: false) == 1.0)
    var chosen = masked
    chosen.strength = 0.4
    #expect(PipelineInputs.strength(tab: chosen, replacesStart: true, editModel: false, hasMargins: false) == 0.4)
  }
}

@MainActor
struct PluginSwitchOffTests {
  let root = PluginFixture.folder()
  let target = FakeContributionTarget()

  func started() throws -> (PluginRegistry, FakeLoader) {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let settings = PluginSettingsStore(fileURL: root.deletingLastPathComponent().appendingPathComponent("off-\(root.lastPathComponent).json"))
    settings.save(["a"])
    let loader = FakeLoader()
    let registry = PluginRegistry(folder: PluginFolder(root: root), settings: settings, loader: loader, tempFolder: root)
    registry.contributions.target = target
    registry.start()
    return (registry, loader)
  }

  func contribute(_ registry: PluginRegistry, _ loader: FakeLoader) async throws {
    _ = await (try #require(loader.host)).receive(
      Data(#"{"type":"contribute","fields":{"steps":4},"pipeline":{"steps":[{"title":"x"}]}}"#.utf8), from: "a")
    #expect(registry.contributions.marks[.steps] != nil && registry.contributions.pipeline != nil)
  }

  @Test func turningAPluginOffInPreferencesTakesItsMarksAndStopsItContributing() async throws {
    let (registry, loader) = try started()
    try await contribute(registry, loader)
    registry.setEnabled("a", false)
    #expect(registry.contributions.marks.isEmpty && registry.contributions.pipeline == nil)
    let reply = await (try #require(loader.host)).receive(Data(#"{"type":"contribute","fields":{"steps":9}}"#.utf8), from: "a")
    #expect(PluginMessageType.of(reply) == PluginMessageType.error)
    #expect(target.fields.parameters.steps == 4)
  }

  @Test func removingAPluginTakesItsMarksAndItsPipeline() async throws {
    let (registry, loader) = try started()
    try await contribute(registry, loader)
    try registry.remove("a")
    #expect(registry.contributions.marks.isEmpty && registry.contributions.pipeline == nil)
  }
}
