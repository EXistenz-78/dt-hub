import Foundation
import HubKit
import Testing

@testable import HubCore

struct PipelineSizesTests {
  func size(_ width: Int, _ height: Int) -> Size { Size(width: width, height: height) }

  @Test func theFirstPassKeepsTheTabsSizeAndTheOthersScaleThePreviousOne() {
    #expect(
      PipelineSizes.sizes(first: size(1024, 1024), scales: [1, 2, 1], limits: [2048, 2048, 2048])
        == [size(1024, 1024), size(2048, 2048), size(2048, 2048)])
  }

  @Test func theScaleOfTheFirstPassIsIgnored() {
    #expect(PipelineSizes.sizes(first: size(1024, 1024), scales: [3, 1], limits: [2048, 2048]) == [size(1024, 1024), size(1024, 1024)])
  }

  @Test func aSizeBeyondTheLimitComesBackKeepingTheRatio() {
    #expect(PipelineSizes.scaled(size(1024, 1024), by: 3, limit: 2048) == size(2048, 2048))
    #expect(PipelineSizes.scaled(size(832, 1216), by: 3, limit: 2048) == size(1408, 2048))
    #expect(PipelineSizes.scaled(size(1216, 832), by: 3, limit: 2048) == size(2048, 1408))
  }

  @Test func withHiResTheLimitIs8192() {
    #expect(
      PipelineSizes.sizes(first: size(1024, 1024), scales: [1, 4, 4], limits: [2048, 8192, 8192])
        == [size(1024, 1024), size(4096, 4096), size(8192, 8192)])
  }

  @Test func sidesAreMultiplesOf64() {
    #expect(PipelineSizes.scaled(size(832, 1216), by: 1.5, limit: 2048) == size(1280, 1856))
    #expect(PipelineSizes.scaled(size(64, 64), by: 0.25, limit: 2048) == size(64, 64))
    #expect(PipelineSizes.scaled(size(1024, 768), by: 0.5, limit: 2048) == size(512, 384))
  }

  @Test func eachPassFitsItsOwnLimit() {
    #expect(PipelineSizes.sizes(first: size(4096, 2048), scales: [1], limits: [2048]) == [size(2048, 1024)])
    #expect(
      PipelineSizes.sizes(first: size(4096, 4096), scales: [1, 1], limits: [8192, 2048]) == [size(4096, 4096), size(2048, 2048)])
  }
}

struct PipelineStepStrengthTests {
  var tab: ControlInputs {
    var inputs = ControlInputs()
    inputs.strength = 0.5
    return inputs
  }

  @Test func thePassesOwnStrengthWins() {
    #expect(PipelineInputs.strength(tab: tab, replacesStart: true, editModel: false, hasMargins: false, step: 0.3) == 0.3)
    #expect(PipelineInputs.strength(tab: tab, replacesStart: true, editModel: true, hasMargins: true, step: 0.3) == 0.3)
  }

  @Test func withoutItTheStrengthIsTheOneOfToday() {
    #expect(PipelineInputs.strength(tab: tab, replacesStart: true, editModel: false, hasMargins: false, step: nil) == 0.5)
    #expect(PipelineInputs.strength(tab: tab, replacesStart: true, editModel: false, hasMargins: false) == 0.5)
    #expect(PipelineInputs.strength(tab: ControlInputs(), replacesStart: true, editModel: false, hasMargins: false) == 0.7)
    #expect(PipelineInputs.strength(tab: ControlInputs(), replacesStart: true, editModel: true, hasMargins: false) == 1)
  }

  @Test func itIsKeptWithinZeroAndOne() {
    #expect(PipelineInputs.strength(tab: tab, replacesStart: true, editModel: false, hasMargins: false, step: 1.4) == 1)
    #expect(PipelineInputs.strength(tab: tab, replacesStart: true, editModel: false, hasMargins: false, step: -2) == 0)
  }
}

@MainActor
struct PipelineStepModelTests {
  let catalog = ModelCatalog(models: [CatalogModel(file: "flux.ckpt", name: "Flux", family: "flux2_9b")], loras: [], fileCount: 1)
  let presets: [String: Preset] = [
    "Q": Preset(name: "Q", model: "qwen.ckpt"), "F": Preset(name: "F", model: "flux.ckpt"), "N": Preset(name: "N"),
  ]

  func user(_ preset: String) -> PipelineStep { PipelineStep(preset: preset, usesPresetModel: true) }

  @Test func aUsersPassRunsWithTheModelOfItsPreset() {
    #expect(PipelinePresets.model(for: user("Q"), presets: presets, header: "flux.ckpt") == "qwen.ckpt")
  }

  @Test func withoutAModelInThePresetTheHeadersIsUsed() {
    #expect(PipelinePresets.model(for: user("N"), presets: presets, header: "flux.ckpt") == "flux.ckpt")
    #expect(PipelinePresets.model(for: user(""), presets: presets, header: "flux.ckpt") == "flux.ckpt")
    #expect(PipelinePresets.model(for: user("N"), presets: presets, header: nil) == nil)
  }

  @Test func aPluginsPassAlwaysRunsWithTheHeadersModel() {
    #expect(PipelinePresets.model(for: PipelineStep(preset: "Q"), presets: presets, header: "flux.ckpt") == "flux.ckpt")
  }

  @Test func theModelsTheServerDoesNotHaveAreListedOnce() {
    let pipeline = PluginPipeline(steps: [user(""), user("Q"), user("F"), user("Q"), user("N")])
    #expect(PipelinePresets.missingModels(in: pipeline, presets: presets, catalog: catalog) == ["qwen.ckpt"])
    #expect(PipelinePresets.missingModels(in: PluginPipeline(steps: [user("F"), user("N")]), presets: presets, catalog: catalog).isEmpty)
  }

  @Test func aPluginsPipelineNeverMissesAModel() {
    let pipeline = PluginPipeline(steps: [PipelineStep(preset: "Q")])
    #expect(PipelinePresets.missingModels(in: pipeline, presets: presets, catalog: catalog).isEmpty)
  }
}
