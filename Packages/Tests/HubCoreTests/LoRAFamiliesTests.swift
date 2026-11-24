import Foundation
import HubKit
import Testing

@testable import HubCore

/// Ming-Image runs the Z-Image LoRAs (same DiT) by family, not file by file; the reverse does not hold.
struct LoRAFamiliesTests {
  private let catalog = ModelCatalog(
    models: [],
    loras: [
      CatalogLoRA(file: "z.ckpt", name: "Z style", family: "z_image"),
      CatalogLoRA(file: "z_new.ckpt", name: "A Z added later", family: "z_image"),
      CatalogLoRA(file: "m.ckpt", name: "Ming own", family: "ming_image"),
      CatalogLoRA(file: "f.ckpt", name: "Flux", family: "flux2_9b"),
      CatalogLoRA(file: "u.ckpt", name: "Unknown", family: nil),
    ], fileCount: 5)

  @Test func mingImageRunsEveryZImageLoRA() {
    #expect(catalog.status(of: LoRASelection(file: "z.ckpt"), family: "ming_image") == .usable)
    #expect(catalog.status(of: LoRASelection(file: "z_new.ckpt"), family: "ming_image") == .usable)
    #expect(catalog.status(of: LoRASelection(file: "m.ckpt"), family: "ming_image") == .usable)
    #expect(catalog.status(of: LoRASelection(file: "f.ckpt"), family: "ming_image") == .otherFamily("flux2_9b"))
  }

  @Test func zImageDoesNotRunMingImageLoRAs() {
    #expect(catalog.status(of: LoRASelection(file: "m.ckpt"), family: "z_image") == .otherFamily("ming_image"))
    #expect(catalog.status(of: LoRASelection(file: "z.ckpt"), family: "z_image") == .usable)
  }

  @Test func theMingImagePickerOffersZImageLoRAsThenUnknownOnes() {
    #expect(catalog.loras(for: "ming_image").map(\.file) == ["z_new.ckpt", "m.ckpt", "z.ckpt", "u.ckpt"])
    #expect(catalog.loras(for: "z_image").map(\.file) == ["z_new.ckpt", "z.ckpt", "u.ckpt"])
  }

  @Test func aZImageLoRAIsSentWithAMingImageModel() {
    var parameters = GenerationParameters()
    parameters.loras = [LoRASelection(file: "z.ckpt"), LoRASelection(file: "f.ckpt")]
    #expect(parameters.loras.filter { catalog.status(of: $0, family: "ming_image") == .usable }.map(\.file) == ["z.ckpt"])
  }

  @Test func theAgentSeesTheModelFamiliesALoRARunsOn() {
    #expect(LoRAFamilies.modelFamilies(runningLoRAsOf: "z_image") == ["z_image", "ming_image"])
    #expect(LoRAFamilies.modelFamilies(runningLoRAsOf: "ming_image") == ["ming_image"])
    #expect(LoRAFamilies.modelFamilies(runningLoRAsOf: "flux2_9b") == ["flux2_9b"])
  }
}
