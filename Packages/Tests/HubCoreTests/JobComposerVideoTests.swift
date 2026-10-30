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

  @Test func h3KeepsTeaCacheAndSolAttentionWithoutSpecCoefficients() {
    var parameters = GenerationParameters()
    parameters.advanced.teaCache = true
    parameters.advanced.teaCacheStart = 7
    parameters.advanced.teaCacheEnd = 20
    parameters.advanced.teaCacheThreshold = 0.4
    parameters.video.usesSolAttention = true
    // A bundled H3 spec has no tea_cache_coefficients.
    let h3 = CatalogModel(
      file: "minimax_h3.ckpt", name: "H3", family: "minimax_h3",
      capabilities: ModelCapabilities(
        guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
        clipSkip: false, nativeSize: 512))
    let result = jobs(h3, parameters)
    #expect(result.allSatisfy { $0.parameters.advanced.teaCache && $0.parameters.advanced.teaCacheStart == 7 })
    #expect(result.allSatisfy { $0.parameters.advanced.teaCacheEnd == 20 && $0.parameters.advanced.teaCacheThreshold == 0.4 })
    #expect(result.allSatisfy { $0.parameters.video.usesSolAttention })
  }

  @Test func videoJobsNeverCarryAMask() {
    var parameters = GenerationParameters()
    parameters.batchCount = 1
    let catalog = ModelCatalog(models: [ltx, h3, flux], loras: [], fileCount: 3)
    func masks(_ model: CatalogModel) -> [MaskSettings?] {
      JobComposer.batches(
        prompt: "p", negativePrompt: "", model: model.file, family: model.family, parameters: parameters,
        catalog: catalog, maskSettings: MaskSettings()) { 1 }.map(\.maskSettings)
    }
    #expect(masks(h3).allSatisfy { $0 == nil } && masks(ltx).allSatisfy { $0 == nil })
    #expect(masks(flux).allSatisfy { $0 != nil })
  }

  @Test func imageToVideoSendsFullStrength() {
    let inputs = ControlInputs()
    let edit = JobComposer.usesFullStrength(editModel: false, family: "minimax_h3")
    #expect(inputs.effectiveStrength(editModel: edit) == 1)
    #expect(JobComposer.usesFullStrength(editModel: false, family: "ltx2.3"))
    #expect(!JobComposer.usesFullStrength(editModel: false, family: "flux2_9b"))
    #expect(inputs.effectiveStrength(editModel: JobComposer.usesFullStrength(editModel: false, family: "flux2_9b")) == 0.7)
    #expect(JobComposer.usesFullStrength(editModel: true, family: "flux2_9b"))
  }
}
