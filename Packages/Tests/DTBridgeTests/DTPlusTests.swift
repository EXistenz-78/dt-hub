import CoreGraphics
import DrawThingsClient
import Foundation
import HubKit
import Testing

@testable import DTBridge

struct CloudImagesTests {
  func image(_ side: Int) -> CGImage {
    CGContext(
      data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
  }

  /// In Bridge Mode the cloud sends the image several times while it works: those are the preview, not results.
  @Test func anImageOnTheWayIsAPreview() throws {
    let update = try JobMapper.update(for: .image(image(4), index: 0))
    guard case .preview(let preview)? = update else {
      Issue.record("not a preview")
      return
    }
    #expect(preview.width == 4)
  }

  @Test func onlyTheLastImagesAskedForAreTheResult() {
    let nine = (1...9).map(image)
    #expect(JobMapper.finalImages(nine, expected: 1).map(\.width) == [9])
    #expect(JobMapper.finalImages(nine, expected: 4).map(\.width) == [6, 7, 8, 9])
    // A local server sends exactly what was asked for: nothing changes.
    #expect(JobMapper.finalImages([image(1), image(2)], expected: 2).map(\.width) == [1, 2])
    #expect(JobMapper.finalImages([image(1)], expected: 0).map(\.width) == [1])
  }
}

struct RemoteModelsTests {
  let installed = ModelCatalog(
    models: [CatalogModel(file: "qwen_image_2.1_i8x.ckpt", name: "Qwen Image 2.1 (8-bit S)", family: "qwen_image_2.1")],
    loras: [CatalogLoRA(file: "x_lora_f16.ckpt", name: "X", family: "flux1")], fileCount: 3, upscalers: ["4x_ultrasharp_f16.ckpt"])
  let live: [String: Data] = [
    "qwen_image_2.1_i8x.ckpt": Data(#"{"file":"qwen_image_2.1_i8x.ckpt","name":"Live name","version":"qwen_image_2.1"}"#.utf8),
    "qwen_image_2.1_q8p.ckpt": Data(#"{"file":"qwen_image_2.1_q8p.ckpt","name":"Qwen Image 2.1","version":"qwen_image_2.1","default_scale":24}"#.utf8),
    "krea_2_raw_q6p.ckpt": Data(#"{"file":"krea_2_raw_q6p.ckpt","name":"Krea 2 Raw (6-bit)","version":"krea_2"}"#.utf8),
  ]

  @Test func theModelsOfTheListsThatAreNotInstalledAreAddedAsRemote() {
    let catalog = CatalogBuilder.addingRemoteModels(to: installed, live: live)
    #expect(catalog.models.count == 3)
    let local = catalog.model(forFile: "qwen_image_2.1_i8x.ckpt")
    #expect(local?.isRemote == false && local?.name == "Qwen Image 2.1 (8-bit S)")
    let q8p = catalog.model(forFile: "qwen_image_2.1_q8p.ckpt")
    #expect(q8p?.isRemote == true && q8p?.name == "Qwen Image 2.1" && q8p?.family == "qwen_image_2.1")
    #expect(q8p?.capabilities.nativeSize == 24 * 64)
    #expect(catalog.model(forFile: "krea_2_raw_q6p.ckpt")?.family == "krea_2")
  }

  @Test func everythingElseOfTheCatalogStays() {
    let catalog = CatalogBuilder.addingRemoteModels(to: installed, live: live)
    #expect(catalog.loras == installed.loras && catalog.upscalers == installed.upscalers && catalog.fileCount == 3)
    #expect(CatalogBuilder.addingRemoteModels(to: installed, live: [:]) == installed)
  }

  @Test func aRemoteModelPassesTheRunCheck() {
    let catalog = CatalogBuilder.addingRemoteModels(to: installed, live: live)
    #expect(RunAvailabilityProbe.blocked(model: "qwen_image_2.1_q8p.ckpt", in: installed))
    #expect(!RunAvailabilityProbe.blocked(model: "qwen_image_2.1_q8p.ckpt", in: catalog))
  }

  @Test func theCommunityListHasItsOwnAddress() {
    #expect(LiveModelList.communityAddress.absoluteString == "https://models.drawthings.ai/uncurated_models.json")
  }
}

/// Without HubCore here: a model is runnable when the catalog has it, which is what `RunAvailability` checks.
enum RunAvailabilityProbe {
  static func blocked(model: String, in catalog: ModelCatalog) -> Bool { catalog.model(forFile: model) == nil }
}

/// With DT+ on, the models are those the cloud has (its echo at compute.drawthings.ai), the LoRAs the local ones
/// plus the cloud's.
struct CloudCatalogTests {
  let local = ModelCatalog(
    models: [
      CatalogModel(file: "qwen_image_2.1_i8x.ckpt", name: "Qwen 2.1 i8x", family: "qwen_image_2.1"),
      CatalogModel(file: "qwen_image_2.1_q8p.ckpt", name: "Qwen 2.1 q8p", family: "qwen_image_2.1"),
    ],
    loras: [
      CatalogLoRA(file: "mine_lora_f16.ckpt", name: "Mine", family: "qwen_image_2.1", trigger: "mn"),
      CatalogLoRA(file: "flux_1_canny_dev_lora_f16.ckpt", name: "Canny (local)", family: "flux1"),
    ],
    fileCount: 9, upscalers: ["4x_ultrasharp_f16.ckpt"])
  let specs: [String: Data] = [
    "flux_2_klein_9b_f16.ckpt": Data(#"{"file":"flux_2_klein_9b_f16.ckpt","name":"FLUX.2 [klein] 9B","version":"flux2_9b"}"#.utf8),
    "not_in_cloud_f16.ckpt": Data(#"{"file":"not_in_cloud_f16.ckpt","name":"Nope","version":"flux1"}"#.utf8),
  ]
  let cloudFiles: Set<String> = [
    "qwen_image_2.1_q8p.ckpt", "flux_2_klein_9b_f16.ckpt", "t5_xxl_encoder_q6p.ckpt", "flux_1_canny_dev_lora_f16.ckpt",
    "hyper_sdxl_8_step_lora_f16.ckpt", "flash_sd3_lora_f16.ckpt",
  ]
  let cloudLoRAs = [
    CatalogLoRA(file: "flux_1_canny_dev_lora_f16.ckpt", name: "FLUX.1 Canny", family: "flux1"),
    CatalogLoRA(file: "hyper_sdxl_8_step_lora_f16.ckpt", name: "Hyper SDXL 8", family: "sdxl_base_v0.9"),
    CatalogLoRA(file: "gone_lora_f16.ckpt", name: "Not in the cloud", family: "flux1"),
  ]

  var catalog: ModelCatalog {
    CatalogBuilder.cloudCatalog(local: local, specs: specs, cloudFiles: cloudFiles, cloudLoRAs: cloudLoRAs)
  }

  @Test func onlyTheModelsOfTheCloudAreListed() {
    #expect(catalog.models.map(\.file).sorted() == ["flux_2_klein_9b_f16.ckpt", "qwen_image_2.1_q8p.ckpt"])
    let klein = catalog.models.first { $0.file == "flux_2_klein_9b_f16.ckpt" }
    #expect(klein?.isRemote == true && klein?.family == "flux2_9b")
    // Downloaded too: it keeps what the server says of it, no cloud mark.
    #expect(catalog.models.first { $0.file == "qwen_image_2.1_q8p.ckpt" }?.isRemote == false)
  }

  @Test func theLoRAsAreTheLocalOnesAndTheCloudOnes() {
    let loras = Dictionary(uniqueKeysWithValues: catalog.loras.map { ($0.file, $0) })
    #expect(Set(loras.keys) == [
      "mine_lora_f16.ckpt", "flux_1_canny_dev_lora_f16.ckpt", "hyper_sdxl_8_step_lora_f16.ckpt", "flash_sd3_lora_f16.ckpt",
    ])
    // A LoRA in both keeps the local description (trigger, weight of the user's server).
    #expect(loras["flux_1_canny_dev_lora_f16.ckpt"]?.name == "Canny (local)")
    // Not in loras.json: the family comes from the name.
    #expect(loras["flash_sd3_lora_f16.ckpt"]?.family == "sd3")
    #expect(catalog.upscalers == local.upscalers && catalog.fileCount == local.fileCount)
  }

  @Test func theFamilyOfALoRAFromItsName() {
    #expect(CatalogBuilder.inferredFamily(ofLoRA: "hyper_sd_v1.x_2_step_lora_f16.ckpt") == "v1")
    #expect(CatalogBuilder.inferredFamily(ofLoRA: "lcm_sd_v1.5_lora_f16.ckpt") == "v1")
    #expect(CatalogBuilder.inferredFamily(ofLoRA: "sdxl_lightning_2_step_lora_f16.ckpt") == "sdxl_base_v0.9")
    #expect(CatalogBuilder.inferredFamily(ofLoRA: "layer_xl_fg2ble_v1.0_lora_f16.ckpt") == "sdxl_base_v0.9")
    #expect(CatalogBuilder.inferredFamily(ofLoRA: "fooocus_inpaint_v2.6_lora_q8p.ckpt") == "sdxl_base_v0.9")
    #expect(CatalogBuilder.inferredFamily(ofLoRA: "lcm_sd_xl_refiner_1.0_lora_f16.ckpt") == nil)
    #expect(CatalogBuilder.inferredFamily(ofLoRA: "ltx_2.3_22b_distilled_lora_f16.ckpt") == "ltx2.3")
    #expect(CatalogBuilder.inferredFamily(ofLoRA: "wan_2.1_14b_self_forcing_t2v_lora_f16.ckpt") == "wan_v2.1_14b")
    #expect(CatalogBuilder.inferredFamily(ofLoRA: "something_else_lora_f16.ckpt") == nil)
  }

  @Test func theCloudListIsTheFilesOfTheEcho() async throws {
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("dtplus-\(UUID()).json")
    let cloud = CloudCatalog(
      filesCache: cache, lorasCache: cache.appendingPathExtension("loras"),
      echo: { ["a.ckpt", "b_lora_f16.ckpt"] },
      download: { _ in Data(#"[{"file":"b_lora_f16.ckpt","name":"B","version":"flux1","prefix":" bb "}]"#.utf8) })
    #expect(await cloud.files() == ["a.ckpt", "b_lora_f16.ckpt"])
    let loras = await cloud.loras()
    #expect(loras.map(\.file) == ["b_lora_f16.ckpt"] && loras.first?.trigger == "bb")
    // Kept on disk: the next launch has it even when the cloud does not answer.
    let offline = CloudCatalog(
      filesCache: cache, lorasCache: cache.appendingPathExtension("loras"),
      echo: { throw URLError(.notConnectedToInternet) }, download: { _ in throw URLError(.notConnectedToInternet) })
    #expect(await offline.files() == ["a.ckpt", "b_lora_f16.ckpt"])
  }

  @Test func withoutTheCloudListThereIsNothingToFilterWith() async {
    let cloud = CloudCatalog(
      filesCache: FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID()).json"),
      lorasCache: FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID()).json"),
      echo: { throw URLError(.timedOut) }, download: { _ in throw URLError(.timedOut) })
    #expect(await cloud.files() == nil)
  }
}
