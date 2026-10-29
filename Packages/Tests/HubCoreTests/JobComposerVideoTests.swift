import HubKit
import Testing

@testable import HubCore

struct JobComposerVideoTests {
  let ltx = CatalogModel(file: "ltx_2.3.ckpt", name: "LTX 2.3", family: "ltx2.3")
  let h3 = CatalogModel(file: "minimax_h3.ckpt", name: "H3", family: "minimax_h3")
  let flux = CatalogModel(file: "flux_2_klein_9b_f16.ckpt", name: "FLUX.2", family: "flux2_9b")

  func jobs(_ model: CatalogModel, _ parameters: GenerationParameters) -> [GenerationJob] {
    let catalog = ModelCatalog(models: [ltx, h3, flux], loras: [], fileCount: 3)
    return JobComposer.batches(
      prompt: "p", negativePrompt: "", model: model.file, family: model.family,
      parameters: parameters, catalog: catalog) { 1 }
  }

  @Test func videoJobCarriesFpsAndSnappedFrames() {
    var parameters = GenerationParameters()
    parameters.batchCount = 2
    parameters.video.numFrames = 100
    let result = jobs(ltx, parameters)
    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.parameters.video.numFrames == 97 && $0.videoFPS == 25 })
  }

  @Test func switchingToAnImageModelResetsVideoParameters() {
    var parameters = GenerationParameters()
    parameters.video.numFrames = 124
    parameters.video.shiftForAudio = 8
    parameters.video.usesSolAttention = true
    let result = jobs(flux, parameters)
    #expect(result.allSatisfy { $0.parameters.video == .default && $0.videoFPS == nil })
  }

  @Test func batchSizeIsOneForVideo() {
    var parameters = GenerationParameters()
    parameters.batchSize = 4
    parameters.batchCount = 3
    let result = jobs(h3, parameters)
    #expect(result.count == 3)
    #expect(result.allSatisfy { $0.parameters.batchSize == 1 && $0.videoFPS == 24 })
  }

  @Test func ltxDoesNotKeepH3Accelerators() {
    var parameters = GenerationParameters()
    parameters.video.usesSolAttention = true
    parameters.video.shiftForAudio = 8
    parameters.advanced.teaCache = true
    let result = jobs(ltx, parameters)
    #expect(result.allSatisfy { !$0.parameters.video.usesSolAttention && !$0.parameters.advanced.teaCache })
    #expect(result.allSatisfy { $0.parameters.video.shiftForAudio == 3 })
  }
}
