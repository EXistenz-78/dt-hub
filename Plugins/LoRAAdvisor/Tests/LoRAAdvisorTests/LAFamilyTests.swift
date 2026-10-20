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
    ("krea_2", "Anima"), ("krea_2", "Chroma"), ("z_image", "Ernie"), ("flux2_9b", "Anima"),
  ])
  func aBaseModelOfAnotherFamilyDoesNot(family: String, base: String) {
    #expect(!LAFamily.fits(baseModel: base, family: family))
  }

  @Test func whenInDoubtTheResultIsKept() {
    #expect(LAFamily.fits(baseModel: "Other", family: "krea_2"))
    #expect(LAFamily.fits(baseModel: "MiniMax H3", family: "krea_2"))
    #expect(LAFamily.fits(baseModel: "Ernie", family: "ernie_image"))
    #expect(LAFamily.fits(baseModel: nil, family: "krea_2"))
    #expect(LAFamily.fits(baseModel: "SD 1.5", family: nil))
    #expect(LAFamily.fits(baseModel: "SD 1.5", family: "something_new"))
  }
}

struct LAFamilyWordsTests {
  @Test func theWordsAuthorsUseForAFamily() {
    #expect(LAFamily.label(ofFamily: "krea_2") == "Krea 2")
    #expect(LAFamily.label(ofFamily: "z_image") == "Z-Image")
    #expect(LAFamily.label(ofFamily: "flux2_9b") == "Klein 9B")
    #expect(LAFamily.label(ofFamily: "qwen_image_2.1") == "Qwen")
    #expect(LAFamily.label(ofFamily: nil) == nil && LAFamily.label(ofFamily: "something_new") == nil)
  }

  @Test func aTitleWithoutTheWordsOfItsFamily() {
    #expect(LAFamily.withoutFamilyWords("[KREA 2] Detail Slider", family: "krea_2") == "Detail Slider")
    #expect(LAFamily.withoutFamilyWords("[ZIT] Detail Slider", family: "z_image") == "Detail Slider")
    #expect(LAFamily.withoutFamilyWords("Detail slider for Z-Image Turbo", family: "z_image") == "Detail slider for")
    #expect(LAFamily.withoutFamilyWords("Flux.2 Klein 9B Consistency", family: "flux2_9b") == "Consistency")
    #expect(LAFamily.withoutFamilyWords("K2 Detail Slider", family: "krea_2") == "Detail Slider")
    #expect(LAFamily.withoutFamilyWords("q21 anything2anime", family: "qwen_image_2.1") == "anything2anime")
    // Only whole words go: a name that merely holds the letters stays.
    #expect(LAFamily.withoutFamilyWords("Kreativ Klein Art", family: "krea_2") == "Kreativ Klein Art")
    #expect(LAFamily.withoutFamilyWords("[KREA 2] Detail Slider", family: nil) == "[KREA 2] Detail Slider")
    #expect(LAFamily.withoutFamilyWords("Krea 2", family: "krea_2") == "")
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

  /// The family's words in the query drown the name ("Z-Image Calypso" finds every Z-Image LoRA): the name is searched
  /// alone, and what shares no word with it is not offered, even if it is for our model.
  @Test func theNameIsSearchedAloneAndUnrelatedResultsAreNotOffered() async {
    let lora = DTHubCatalogLoRA(file: "zit_calypso_aesthetic_v6.ckpt", name: "ZIT Calypso_Aesthetic_v6", family: "z_image")
    serve("Calypso Aesthetic v6", [])
    serve("Calypso Aesthetic", [
      (1, "Calypso (Bluey)", "ZImageTurbo"), (2, "Z-Image GodPussy", "ZImageTurbo"), (3, "Calypso Aesthetic Style", "ZImageTurbo"),
      (4, "Calypso Aesthetic XL", "Pony"),
    ])
    serve("Z-Image Calypso Aesthetic v6", [(2, "Z-Image GodPussy", "ZImageTurbo"), (5, "Z-Image Turbo NSFW LoRA", "ZImageTurbo")])
    await jobs.searchAll([lora])
    #expect(store.entry(for: lora.file).candidates.map(\.title) == ["Calypso Aesthetic Style", "Calypso (Bluey)"])
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

  /// One page often holds the same LoRA for several models, each as a version: the version for ours is the one to take.
  @Test func theVersionForOurModelIsTheOneLinked() async {
    let lora = DTHubCatalogLoRA(file: "k2_detail_slider.ckpt", name: "K2 Detail Slider", family: "krea_2")
    let items = """
      {"items":[
        {"id":1,"name":"Detail Slider","modelVersions":[{"id":11,"baseModel":"SD 1.5"},{"id":12,"baseModel":"SD 1.5"}]},
        {"id":2,"name":"Detail Slider","modelVersions":[{"id":21,"baseModel":"SDXL 1.0"},{"id":22,"baseModel":"Krea 2"}]}
      ]}
      """
    fetcher.set(LACivitai.searchURL("Detail Slider"), text: items)
    fetcher.set(
      LACivitai.modelURL(2),
      text: #"{"description":"<p>Sliders</p>","modelVersions":[{"id":21,"baseModel":"SDXL 1.0","images":[]},{"id":22,"name":"Krea","baseModel":"Krea 2","images":[]}]}"#)
    await jobs.searchAll([lora])
    let entry = store.entry(for: lora.file)
    #expect(entry.link == "https://civitai.com/models/2?modelVersionId=22")
    #expect(entry.notes.contains("Base model: Krea 2"))
  }

  @Test func aCandidateSaysTheVersionThatFits() {
    let json = #"{"items":[{"id":2,"name":"Multi","modelVersions":[{"id":21,"baseModel":"SDXL 1.0"},{"id":22,"baseModel":"Krea 2"}]},{"id":3,"name":"First fits","modelVersions":[{"id":31,"baseModel":"Krea 2"},{"id":32,"baseModel":"SD 1.5"}]},{"id":4,"name":"None fits","modelVersions":[{"id":41,"baseModel":"SD 1.5"}]},{"id":5,"name":"No versions"}]}"#
    #expect(
      LACivitai.candidates(json: Data(json.utf8), family: "krea_2") == [
        LACandidate(title: "Multi", link: "https://civitai.com/models/2?modelVersionId=22", info: "Krea 2"),
        LACandidate(title: "First fits", link: "https://civitai.com/models/3", info: "Krea 2"),
        LACandidate(title: "No versions", link: "https://civitai.com/models/5"),
      ])
    #expect(LACivitai.candidates(json: Data(json.utf8), family: nil).count == 4)
  }

  /// The real case: "K2 Detail Slider" is "[KREA 2] Detail Slider" on Civitai, found only with the family in the query.
  @Test func theFamilysOwnWordsFindAndMatchThePage() async {
    let lora = DTHubCatalogLoRA(file: "k2_detail_slider.ckpt", name: "K2 Detail Slider", family: "krea_2")
    serve("Krea 2 Detail Slider", [(2_729_908, "[KREA 2] Detail Slider", "Krea 2"), (2_977_306, "Krea 2 Detail Density Slider", "Krea 2")])
    serve("Detail Slider", [(123_543, "Detail Slider", "SD 1.5")])
    await jobs.searchAll([lora])
    let entry = store.entry(for: lora.file)
    #expect(entry.link == "https://civitai.com/models/2729908" && entry.foundBySearch)
    #expect(!fetcher.requests.contains(LACivitai.searchURL("K2 Detail Slider").absoluteString))
  }

  @Test func withoutAKnownFamilyTheNameIsSearchedAsItIs() async {
    let lora = DTHubCatalogLoRA(file: "x_thing.ckpt", name: "X Thing")
    await jobs.searchAll([lora])
    let asked = fetcher.requests.filter { $0.contains("civitai.com") }
    #expect(asked == [LACivitai.searchURL("Thing").absoluteString, LACivitai.searchURL("X Thing").absoluteString])
  }

  @Test func aLoRAOfUnknownFamilyKeepsEveryResult() async {
    let lora = DTHubCatalogLoRA(file: "x_thing.ckpt", name: "X Thing")
    serve("Thing", [(1, "Thing one", "SD 1.5"), (2, "Thing two", "Krea 2")])
    await jobs.searchAll([lora])
    #expect(store.entry(for: lora.file).candidates.count == 2)
  }
}
