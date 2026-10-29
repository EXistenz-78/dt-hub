import Foundation
import HubKit
import Testing

@testable import DTBridge

struct CatalogBuilderTests {
  let klein = "flux_2_klein_9b_f16.ckpt"
  let vae = "flux_2_vae_f16.ckpt"
  let describedLoRA = "sun_direction_lora_f16.ckpt"
  let bareLoRA = "hyper_sdxl_8_step_lora_f16.ckpt"
  let specs = ["flux_2_klein_9b_f16.ckpt": ModelSpecInfo(name: "FLUX.2 [klein] 9B", family: "flux2_9b")]
  let loraJSON = Data(
    """
    [{"file": "sun_direction_lora_f16.ckpt", "name": "Sun direction", "version": "flux2_9b",
      "prefix": "match the sun direction ", "weight": 0.8},
     {"file": "not_installed_lora_f16.ckpt", "name": "Gone", "version": "flux2_9b"},
     {"name": "No file"}]
    """.utf8)

  @Test func readsTheModifierOfAModel() {
    #expect(CatalogBuilder.capabilities(["modifier": "kontext"]).modifier == "kontext")
    #expect(CatalogBuilder.capabilities(["modifier": "kontext"]).isEditModel)
    #expect(CatalogBuilder.capabilities([:]).modifier == nil)
    #expect(!CatalogBuilder.capabilities(["modifier": "inpainting"]).isEditModel)
  }

  @Test func modelsAreTheFilesWithASpec() {
    let catalog = CatalogBuilder.build(
      files: [klein, vae, describedLoRA, bareLoRA], modelSpecs: specs, loraMetadata: loraJSON)
    #expect(catalog.models == [CatalogModel(file: klein, name: "FLUX.2 [klein] 9B", family: "flux2_9b")])
    #expect(catalog.fileCount == 4)
  }

  @Test func loRAsComeFromMetadataPlusUndescribedLoRAFiles() {
    let catalog = CatalogBuilder.build(
      files: [klein, vae, describedLoRA, bareLoRA], modelSpecs: specs, loraMetadata: loraJSON)
    #expect(
      catalog.loras == [
        CatalogLoRA(
          file: describedLoRA, name: "Sun direction", family: "flux2_9b",
          trigger: "match the sun direction", defaultWeight: 0.8),
        CatalogLoRA(file: bareLoRA, name: bareLoRA, family: nil),
      ])
  }

  @Test func unreadableLoRAMetadataIsNotFatal() {
    let catalog = CatalogBuilder.build(
      files: [klein, bareLoRA], modelSpecs: specs, loraMetadata: Data("not json".utf8))
    #expect(catalog.models.count == 1)
    #expect(catalog.loras == [CatalogLoRA(file: bareLoRA, name: bareLoRA, family: nil)])
  }

  @Test func upscalersAndFaceRestorersComeFromTheFileNames() {
    let catalog = CatalogBuilder.build(
      files: [
        klein, vae, "realesrgan_x4plus_f16.ckpt", "4x_ultrasharp_f16.ckpt", "restoreformer_v1.0_f16.ckpt",
        "parsenet_v1.0_f16.ckpt", "ltx_2.3_spatial_upscaler_x1.5_f16.ckpt",
      ],
      modelSpecs: specs, loraMetadata: Data())
    #expect(catalog.upscalers == ["4x_ultrasharp_f16.ckpt", "realesrgan_x4plus_f16.ckpt"])
    #expect(catalog.faceRestorers == ["restoreformer_v1.0_f16.ckpt"])
  }

  /// The Official list (DT+) writes the modifiers in camelCase (`qwenimageEditPlus`), the older lists and the server in
  /// snake_case (`qwenimage_edit_plus`): one spelling inside the app, or Qwen Image Edit 2509 and 2511 of the Official
  /// list were not edit models.
  @Test func bothSpellingsOfTheModifierAreTheSameModel() {
    let expected: [(String, String, Bool)] = [
      ("qwenimageEditPlus", "qwenimage_edit_plus", true), ("qwenimage_edit_plus", "qwenimage_edit_plus", true),
      ("qwenimageEdit2511", "qwenimage_edit_2511", true), ("qwenimage_edit_2511", "qwenimage_edit_2511", true),
      ("kontextKv", "kontext_kv", true), ("kontext_kv", "kontext_kv", true), ("kontext", "kontext", true),
      ("editing", "editing", true), ("qwenimageLayered", "qwenimage_layered", false),
      ("inpainting", "inpainting", false), ("fl2va", "fl2va", false), ("ref2va", "ref2va", false),
    ]
    for (spelled, key, isEdit) in expected {
      let capabilities = CatalogBuilder.capabilities(["modifier": spelled])
      #expect(capabilities.modifier == key, "\(spelled)")
      #expect(capabilities.isEditModel == isEdit, "\(spelled)")
    }
    #expect(CatalogBuilder.capabilities([:]).modifier == nil)
    #expect(CatalogBuilder.capabilities(["modifier": "None"]).modifier == "none", "the Official list's None")
    #expect(!CatalogBuilder.capabilities(["modifier": "None"]).isEditModel)
  }

  @Test func capabilitiesComeFromTheSpec() {
    let flux1 = CatalogBuilder.capabilities([
      "guidance_embed": true, "tea_cache_coefficients": [1.0], "clip_encoder": "clip_vit_l14_f16.ckpt",
      "text_encoder": "t5_xxl_encoder_q6p.ckpt", "default_scale": 16,
    ])
    #expect(flux1 == ModelCapabilities(
      guidanceEmbed: true, teaCache: true, clipL: true, openClipG: false, t5: true,
      optionalT5: false, clipSkip: false, nativeSize: 1024))
    let sd3 = CatalogBuilder.capabilities([
      "clip_encoder": "clip_vit_l14_f16.ckpt", "t5_encoder": "t5_xxl_encoder_q6p.ckpt",
      "text_encoder": "open_clip_vit_bigg14_f16.ckpt", "default_scale": 16,
    ])
    #expect(sd3.clipL && sd3.openClipG && sd3.t5 && sd3.optionalT5 && sd3.clipSkip)
    let klein = CatalogBuilder.capabilities(["text_encoder": "qwen_3_8b_q8p.ckpt", "default_scale": 16])
    #expect(klein == ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false,
      optionalT5: false, clipSkip: false, nativeSize: 1024))
  }

  @Test func noFilesMeansModelBrowsingIsOff() {
    let catalog = CatalogBuilder.build(files: [], modelSpecs: [:], loraMetadata: Data())
    #expect(catalog.isModelBrowsingDisabled)
  }

  @Test func specInfoFallsBackToTheFileName() {
    let named = CatalogBuilder.specInfo(json: Data(#"{"name": "Z Image", "version": "z_image"}"#.utf8), file: "z.ckpt")
    let unnamed = CatalogBuilder.specInfo(json: Data(#"{"file": "z.ckpt"}"#.utf8), file: "z.ckpt")
    #expect(named.name == "Z Image" && named.family == "z_image")
    #expect(unnamed.name == "z.ckpt" && unnamed.family == nil)
  }

  @Test func specInfoReadsTheTextLengthAndTheConsistencyFlag() {
    let json = Data(
      #"{"file":"a.ckpt","name":"A","version":"z_image","padded_text_encoding_length":512,"is_consistency_model":true}"#.utf8)
    let info = CatalogBuilder.specInfo(json: json, file: "a.ckpt")
    #expect(info.capabilities.paddedTextEncodingLength == 512)
    #expect(info.capabilities.isConsistencyModel)
    let plain = CatalogBuilder.specInfo(json: Data(#"{"file":"b.ckpt","version":"z_image"}"#.utf8), file: "b.ckpt")
    #expect(plain.capabilities.paddedTextEncodingLength == 0)
    #expect(!plain.capabilities.isConsistencyModel)
  }

  @Test func specInfoReadsTheDualAttentionLayersOfAnMMDiT() {
    let json = Data(#"{"file":"a.ckpt","version":"sd3","mmdit":{"qk_norm":true,"dual_attention_layers":[0,1,2]}}"#.utf8)
    #expect(CatalogBuilder.specInfo(json: json, file: "a.ckpt").capabilities.dualAttentionLayers == [0, 1, 2])
    let plain = CatalogBuilder.specInfo(json: Data(#"{"file":"b.ckpt","version":"sd3"}"#.utf8), file: "b.ckpt")
    #expect(plain.capabilities.dualAttentionLayers.isEmpty)
  }

  @Test func localVideoModelStaysWhenNotOnCloud() {
    let video = CatalogModel(file: "minimax_h3_ref2va_q8p.ckpt", name: "H3", family: "minimax_h3")
    let image = CatalogModel(file: klein, name: "Klein", family: "flux2_9b")
    let catalog = CatalogBuilder.cloudCatalog(
      local: ModelCatalog(models: [video, image], loras: [], fileCount: 2), specs: [:], sources: [:], deprecated: [],
      cloudFiles: ["other.ckpt"], cloudLoRAs: [])
    #expect(catalog.models.map(\.file) == [video.file])
    #expect(catalog.models.first?.isLocalOnly == true)
    #expect(catalog.models.first?.isRemote == false)
  }

  @Test func listsWinOverBundledSpecs() throws {
    let file = "fasth3_omni_i4x.ckpt"
    let list = Data(#"{"file":"fasth3_omni_i4x.ckpt","name":"From the list","version":"minimax_h3"}"#.utf8)
    let merged = VideoModelSpecs.filling([file: list])
    #expect(merged[file] == list)
    #expect(merged["fasth3_omni_q8p.ckpt"] != nil)
    let sources = CatalogBuilder.sources(
      official: [:], community: [file: list], uncurated: [:], bundled: Set(VideoModelSpecs.byFile.keys))
    #expect(sources[file] == .community)
    #expect(sources["fasth3_omni_q8p.ckpt"] == .community)
    let catalog = CatalogBuilder.addingRemoteModels(to: .empty, live: merged, sources: sources)
    #expect(catalog.model(forFile: file)?.name == "From the list")
    #expect(catalog.model(forFile: "fasth3_omni_q8p.ckpt")?.name != nil)
  }
}
