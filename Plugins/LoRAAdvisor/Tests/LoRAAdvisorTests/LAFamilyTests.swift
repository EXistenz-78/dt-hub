import DTHubPluginKit
import Foundation
import Testing

@testable import LoRAAdvisor

struct LAFamilyTests {
  @Test(arguments: [
    ("krea_2", "Krea 2"), ("z_image", "ZImageTurbo"), ("z_image", "ZImageBase"), ("flux2_9b", "Flux.2 Klein 9B"),
    ("flux2_9b", "Flux.2 Klein 9B-base"), ("flux2_4b", "Flux.2 Klein 4B-base"), ("flux2", "Flux.2 D"), ("flux1", "Flux.1 D"),
    ("flux1", "Flux.1 Krea"), ("qwen_image_2.1", "Qwen 2.1"), ("qwen_image", "Qwen"), ("qwenimage_edit_plus", "Qwen"),
    ("sdxl_base_v0.9", "SDXL 1.0"), ("sdxl_base_v0.9", "Pony"), ("sdxl_base_v0.9", "Illustrious"), ("ssd_1b", "SDXL 1.0"),
    ("v1", "SD 1.5"), ("v1", "SD 1.5 LCM"), ("v2", "SD 2.1"), ("sd3_large", "SD 3.5 Large"), ("hidream_i1", "HiDream"),
  ])
  func aBaseModelOfTheSameFamilyFits(family: String, base: String) {
    #expect(LAFamily.fits(baseModel: base, family: family))
  }

  @Test(arguments: [
    ("krea_2", "SD 1.5"), ("krea_2", "Flux.1 D"), ("krea_2", "Illustrious"), ("krea_2", "Flux.1 Krea"),
    ("z_image", "Pony"), ("flux2_9b", "Flux.2 Klein 4B"), ("flux2_9b", "Flux.2 D"), ("flux2_9b", "Flux.1 D"),
    ("flux2", "Flux.2 Klein 9B"), ("qwen_image_2.1", "SDXL 1.0"), ("v1", "SDXL 1.0"), ("v1", "SD 2.1"),
    ("sdxl_base_v0.9", "SD 1.5"), ("z_image", "Wan Video 2.2 I2V-A14B"), ("krea_2", "Hunyuan Video"),
  ])
  func aBaseModelOfAnotherFamilyDoesNot(family: String, base: String) {
    #expect(!LAFamily.fits(baseModel: base, family: family))
  }

  @Test func whenInDoubtTheResultIsKept() {
    #expect(LAFamily.fits(baseModel: "Other", family: "krea_2"))
    #expect(LAFamily.fits(baseModel: "Chroma", family: "krea_2"))
    #expect(LAFamily.fits(baseModel: nil, family: "krea_2"))
    #expect(LAFamily.fits(baseModel: "SD 1.5", family: nil))
    #expect(LAFamily.fits(baseModel: "SD 1.5", family: "something_new"))
  }
}

@MainActor
struct LAFilteredSearchTests {
  let store = LAStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("la-filter-\(UUID().uuidString)", isDirectory: true))
  let fetcher = FakeFetcher()
  var jobs: LAJobs { LAJobs(store: store, fetcher: fetcher, summarise: { _, _ in nil }, pause: .zero, italian: true) }

  func serve(_ query: String, _ results: [(id: Int, name: String, base: String)]) {
    let items = results.map { #"{"id":\#($0.id),"name":"\#($0.name)","modelVersions":[{"baseModel":"\#($0.base)"}]}"# }.joined(separator: ",")
    fetcher.set(LACivitai.searchURL(query), text: #"{"items":[\#(items)]}"#)
    for result in results {
      fetcher.set(LACivitai.modelURL(result.id), text: #"{"description":"<p>Page \#(result.id)</p>","modelVersions":[{"id":1,"images":[]}]}"#)
    }
  }

  @Test func resultsForAnotherModelAreLeftOut() async {
    let lora = DTHubCatalogLoRA(file: "k2_retropulp.ckpt", name: "K2 Retropulp", family: "krea_2")
    serve("Retropulp", [
      (1, "Retro Pulp one", "SD 1.5"), (2, "Retro Pulp two", "Illustrious"), (3, "Retro Pulp three", "Pony"),
      (4, "Retro Pulp four", "Krea 2"), (5, "Retro Pulp five", "Other"), (6, "Retro Pulp six", "Flux.1 D"),
    ])
    await jobs.searchAll([lora])
    #expect(store.entry(for: lora.file).candidates.map(\.title) == ["Retro Pulp four", "Retro Pulp five"])
  }

  @Test func theSameNameForAnotherModelIsNotLinked() async {
    let lora = DTHubCatalogLoRA(file: "k2_giallo.ckpt", name: "K2 Giallostyle", family: "krea_2")
    serve("Giallostyle", [(1, "Giallostyle", "SD 1.5"), (2, "Giallostyle", "Krea 2")])
    await jobs.searchAll([lora])
    #expect(store.entry(for: lora.file).link == "https://civitai.com/models/2")
    let other = DTHubCatalogLoRA(file: "k2_noir.ckpt", name: "K2 Noirstyle", family: "krea_2")
    serve("Noirstyle", [(7, "Noirstyle", "SDXL 1.0")])
    await jobs.searchAll([other])
    #expect(store.entry(for: other.file) == LAEntry(searched: true))
  }

  @Test func aLoRAOfUnknownFamilyKeepsEveryResult() async {
    let lora = DTHubCatalogLoRA(file: "x_thing.ckpt", name: "X Thing")
    serve("Thing", [(1, "Thing one", "SD 1.5"), (2, "Thing two", "Krea 2")])
    await jobs.searchAll([lora])
    #expect(store.entry(for: lora.file).candidates.count == 2)
  }
}
