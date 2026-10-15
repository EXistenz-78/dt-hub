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
      presets: presets, catalog: catalog, headerModel: (model ?? zimage).file)
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
}
