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
