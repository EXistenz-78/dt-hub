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
    [{"file": "sun_direction_lora_f16.ckpt", "name": "Sun direction", "version": "flux2_9b"},
     {"file": "not_installed_lora_f16.ckpt", "name": "Gone", "version": "flux2_9b"},
     {"name": "No file"}]
    """.utf8)

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
        CatalogLoRA(file: describedLoRA, name: "Sun direction", family: "flux2_9b"),
        CatalogLoRA(file: bareLoRA, name: bareLoRA, family: nil),
      ])
  }

  @Test func unreadableLoRAMetadataIsNotFatal() {
    let catalog = CatalogBuilder.build(
      files: [klein, bareLoRA], modelSpecs: specs, loraMetadata: Data("not json".utf8))
    #expect(catalog.models.count == 1)
    #expect(catalog.loras == [CatalogLoRA(file: bareLoRA, name: bareLoRA, family: nil)])
  }

  @Test func noFilesMeansModelBrowsingIsOff() {
    let catalog = CatalogBuilder.build(files: [], modelSpecs: [:], loraMetadata: Data())
    #expect(catalog.isModelBrowsingDisabled)
  }

  @Test func specInfoFallsBackToTheFileName() {
    let named = CatalogBuilder.specInfo(json: Data(#"{"name": "Z Image", "version": "z_image"}"#.utf8), file: "z.ckpt")
    let unnamed = CatalogBuilder.specInfo(json: Data(#"{"file": "z.ckpt"}"#.utf8), file: "z.ckpt")
    #expect(named == ModelSpecInfo(name: "Z Image", family: "z_image"))
    #expect(unnamed == ModelSpecInfo(name: "z.ckpt", family: nil))
  }
}
