import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct CUPlannerTests {
  let flux = CatalogModel(file: "flux.ckpt", name: "Flux", family: "flux2_9b")
  let zimage = CatalogModel(file: "z.ckpt", name: "Z", family: "z_image")
  let sdxl = CatalogModel(file: "x.ckpt", name: "X", family: "sdxl_base_v0.9")
  var catalog: ModelCatalog {
    ModelCatalog(models: [flux, zimage, sdxl], loras: [], fileCount: 3, upscalers: [])
  }
  let control = CUControlSummary(hasImage: false, moodboardCount: 2, strength: 0.7)

  func fields(width: Int = 1024, height: Int = 1024, steps: Int = 8, batch: Int = 1) -> GenerationFields {
    GenerationFields(parameters: GenerationParameters(width: width, height: height, steps: steps, batchSize: batch))
  }

  func passes(
    _ pipeline: PluginPipeline? = nil, presets: [String: Preset] = [:], model: CatalogModel? = nil,
    fields: GenerationFields? = nil, control: CUControlSummary? = nil
  ) -> [CUPass] {
    CUPlanner.passes(
      fields: fields ?? self.fields(), model: model ?? zimage, control: control ?? self.control, pipeline: pipeline,
      presets: presets, catalog: catalog, headerModel: (model ?? zimage).file,
      strengthOfPass: { _, _, _, _, _ in 0.7 })
  }

  @Test func aSingleRunIsOnePass() throws {
    let result = passes(fields: fields(batch: 2))
    #expect(result.count == 1)
    let inputs = try #require(result[0].inputs)
    #expect(inputs.family == "z_image" && inputs.batchSize == 2 && inputs.width == 1024 && inputs.steps == 8)
    #expect(!inputs.hasImage && inputs.strength == 1)
  }

  @Test func theStrengthCountsOnlyWithAStartImage() throws {
    let withImage = CUControlSummary(hasImage: true, moodboardCount: 0, strength: 0.7)
    #expect(try #require(passes(control: withImage)[0].inputs).strength == 0.7)
  }

  @Test func aPipelineGivesOnePassPerStep() {
    let pipeline = PluginPipeline(steps: [PipelineStep(title: "one"), PipelineStep(title: "two")])
    let result = passes(pipeline)
    #expect(result.map(\.title) == ["one", "two"])
    #expect(result.allSatisfy { $0.inputs != nil })
  }

  @Test func aMissingPresetGivesNoInputsButTheOthersStay() {
    let pipeline = PluginPipeline(steps: [PipelineStep(title: "a", preset: "nope"), PipelineStep(title: "b")])
    let result = passes(pipeline)
    #expect(result[0].inputs == nil)
    #expect(result[1].inputs != nil)
  }

  @Test func aMissingModelGivesNoInputs() {
    let preset = Preset(name: "p", model: "gone.ckpt")
    let pipeline = PluginPipeline(steps: [PipelineStep(title: "a", preset: "p", usesPresetModel: true)])
    #expect(passes(pipeline, presets: ["p": preset])[0].inputs == nil)
  }

  @Test func videoInputsCarryTheFrameCountAndImagesKeepOne() throws {
    let video = CatalogModel(file: "h3.ckpt", name: "H3", family: "minimax_h3")
    let ltx = CatalogModel(file: "ltx.ckpt", name: "LTX", family: "ltx2.3")
    let wan = CatalogModel(file: "wan.ckpt", name: "Wan", family: "wan_v2.2_5b")
    let withVideo = ModelCatalog(models: [flux, zimage, sdxl, video, ltx, wan], loras: [], fileCount: 6, upscalers: [])
    var parameters = GenerationParameters(width: 832, height: 512, steps: 8)
    parameters.video.numFrames = 124
    for model in [video, ltx] {
      let result = CUPlanner.passes(
        fields: GenerationFields(parameters: parameters), model: model, control: control, pipeline: nil,
        presets: [:], catalog: withVideo, headerModel: model.file, strengthOfPass: { _, _, _, _, _ in 0.7 })
      #expect(result.count == 1)
      let inputs = try #require(result[0].inputs)
      #expect(inputs.numFrames == 124)
    }
    // A hidden LTX-2 (a pipeline preset can reach it) gets its frames too.
    let ltx2 = CatalogModel(file: "ltx2.ckpt", name: "LTX2", family: "ltx2")
    let withLtx2 = ModelCatalog(models: [ltx2], loras: [], fileCount: 1, upscalers: [])
    let hidden = CUPlanner.passes(
      fields: GenerationFields(parameters: parameters), model: ltx2, control: control, pipeline: nil, presets: [:],
      catalog: withLtx2, headerModel: ltx2.file, strengthOfPass: { _, _, _, _, _ in 0.7 })
    #expect(try #require(hidden[0].inputs).numFrames == 124)
    // A video family the port does not cover is passed on like any family; the estimator has no estimate for it
    // (ComputeUnitsEstimatorTests.aVideoFamilyThePortDoesNotCoverHasNoEstimate).
    let uncovered = CUPlanner.passes(
      fields: GenerationFields(parameters: parameters), model: wan, control: control, pipeline: nil, presets: [:],
      catalog: withVideo, headerModel: wan.file, strengthOfPass: { _, _, _, _, _ in 0.7 })
    #expect(try #require(uncovered[0].inputs).family == "wan_v2.2_5b")
    // The same request on an image model still has an estimate, and its frame count stays 1.
    let image = try #require(passes(model: zimage)[0].inputs)
    #expect(image.numFrames == 1)
  }

  @Test func theMoodboardCountsOnlyForAFamilyThatUsesIt() throws {
    // SD XL has no Moodboard in DT Hub; FLUX.2 and Z Image do.
    let old = try #require(passes(model: sdxl)[0].inputs)
    #expect(old.referenceImages == 0)
    let modern = try #require(passes(model: flux)[0].inputs)
    #expect(modern.referenceImages == 2)
  }

  @Test func aStepMoodboardOverridesTheTabs() throws {
    let step = PipelineStep(title: "a", moodboard: [])
    #expect(try #require(passes(PluginPipeline(steps: [step]))[0].inputs).referenceImages == 0)
  }

  @Test func theOutputOfThePreviousPassIsTheStartImageFromTheSecondPass() throws {
    let pipeline = PluginPipeline(steps: [
      PipelineStep(title: "a", useOutputAsStart: true), PipelineStep(title: "b", useOutputAsStart: true),
    ])
    let result = passes(pipeline)
    #expect(try #require(result[0].inputs).hasImage == false)
    #expect(try #require(result[1].inputs).hasImage == true)
  }

  @Test func aUserPipelineScalesTheSizeFromTheSecondPass() throws {
    let tab = fields(width: 832, height: 1216)
    let pipeline = PluginPipeline(steps: [
      PipelineStep(title: "a", usesPresetModel: true, scale: 1), PipelineStep(title: "b", usesPresetModel: true, scale: 1.5),
    ])
    let result = passes(pipeline, fields: tab)
    #expect(try #require(result[0].inputs).width == 832)
    let second = try #require(result[1].inputs)
    #expect(second.width == 1280 && second.height == 1856)
  }

  @Test func thePassStrengthIsWhatTheRunWouldSend() throws {
    struct Call: Equatable {
      var title: String
      var replacesStart: Bool
      var editModel: Bool
      var width: Int
      var height: Int
    }
    let editor = CatalogModel(
      file: "edit.ckpt", name: "Edit", family: "flux2_9b",
      capabilities: ModelCapabilities(
        guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
        clipSkip: false, nativeSize: nil, modifier: "kontext"))
    let withEditor = ModelCatalog(models: [flux, zimage, editor], loras: [], fileCount: 3, upscalers: [])
    let preset = Preset(name: "edit", model: "edit.ckpt")
    let pipeline = PluginPipeline(steps: [
      PipelineStep(title: "a"),
      PipelineStep(title: "b", preset: "edit", useOutputAsStart: true, usesPresetModel: true, scale: 1.5),
    ])
    nonisolated(unsafe) var calls: [Call] = []
    let result = CUPlanner.passes(
      fields: fields(width: 832, height: 1216), model: zimage, control: control, pipeline: pipeline,
      presets: ["edit": preset], catalog: withEditor, headerModel: zimage.file,
      strengthOfPass: { step, replacesStart, editModel, width, height in
        calls.append(Call(title: step.title, replacesStart: replacesStart, editModel: editModel, width: width, height: height))
        return 0.42
      })
    #expect(calls == [
      Call(title: "a", replacesStart: false, editModel: false, width: 832, height: 1216),
      Call(title: "b", replacesStart: true, editModel: true, width: 1280, height: 1856),
    ])
    // The first pass has no start image (strength 1); the second has one, with the caller's strength.
    #expect(try #require(result[0].inputs).strength == 1)
    #expect(try #require(result[1].inputs).strength == 0.42)
  }

  @Test func presetsThatLoadAreKeptWhenAnotherIsMissing() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cu-presets-\(UUID())")
    let store = PresetStore(folder: folder)
    try store.save(Preset(name: "good", model: "z.ckpt"))
    let pipeline = PluginPipeline(steps: [PipelineStep(title: "a", preset: "good"), PipelineStep(title: "b", preset: "gone")])
    let loaded = CUPlanner.availablePresets(for: pipeline, from: store)
    #expect(Set(loaded.keys) == ["good"])
  }
}

@MainActor
struct CUPlannerGuidedTests {
  let planner = CUPlannerTests()

  @Test func eachGuidedPassIsMeasuredAsTheEstimate() throws {
    var estimate = PipelineStep()
    estimate.size = PipelineSize(width: 512, height: 768)
    let pipeline = PluginPipeline(name: "g", steps: [], guided: GuidedPipeline(passes: 5, estimate: estimate))
    let result = planner.passes(pipeline)
    #expect(result.count == 5)
    let first = try #require(result[0].inputs)
    #expect(first.width == 512 && first.height == 768)
    #expect(first.hasImage)
    #expect(result.allSatisfy { $0.inputs?.width == 512 })
  }
}
