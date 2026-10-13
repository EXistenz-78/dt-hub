import DTHubPluginKit
import Foundation
import Testing

@testable import LoRAAdvisor

struct LACandidateParsingTests {
  @Test func theNameWithoutItsFirstWord() {
    #expect(LAName.withoutPrefix("K2 Giallostyle") == "Giallostyle")
    #expect(LAName.withoutPrefix("z image calypso aesthetic v6") == "image calypso aesthetic v6")
    #expect(LAName.withoutPrefix("Delta") == nil)
    #expect(LAName.withoutPrefix("  ") == nil)
  }

  @Test func civitaiResultsBecomeCandidates() {
    let json = #"{"items":[{"id":7,"name":"Giallostyle!","modelVersions":[{"baseModel":"Krea 2"}]},{"id":8,"name":"Other"},{"name":"no id"},5]}"#
    #expect(
      LACivitai.candidates(json: Data(json.utf8)) == [
        LACandidate(title: "Giallostyle!", link: "https://civitai.com/models/7", info: "Krea 2"),
        LACandidate(title: "Other", link: "https://civitai.com/models/8"),
      ])
    #expect(LACivitai.candidates(json: Data("x".utf8)).isEmpty)
  }

  @Test func huggingFaceResultsBecomeCandidates() {
    let json = #"[{"id":"dx8152/Flux2-Klein-9B-Consistency","downloads":40308},{"id":"B4100/Flux2-Klein-9B-Consistency"},{"id":"noslash"},7]"#
    #expect(
      LAHuggingFace.candidates(json: Data(json.utf8)) == [
        LACandidate(title: "dx8152/Flux2-Klein-9B-Consistency", link: "https://huggingface.co/dx8152/Flux2-Klein-9B-Consistency", downloads: 40308),
        LACandidate(title: "B4100/Flux2-Klein-9B-Consistency", link: "https://huggingface.co/B4100/Flux2-Klein-9B-Consistency"),
      ])
    #expect(LAHuggingFace.candidates(json: Data("{}".utf8)).isEmpty)
    let url = LAHuggingFace.searchURL("klein 9b&x").absoluteString
    #expect(url.hasPrefix("https://huggingface.co/api/models?search=klein%209b%26x") && url.contains("sort=downloads") && url.contains("limit=5"))
  }
}

@MainActor
struct LACandidatesTests {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("la-cand-\(UUID().uuidString)", isDirectory: true)
  let store: LAStore
  let fetcher = FakeFetcher()
  let jobs: LAJobs
  let state: LAState

  init() {
    store = LAStore(folder: folder)
    jobs = LAJobs(store: store, fetcher: fetcher, summarise: { _, _ in nil }, pause: .zero, italian: true)
    state = LAState(store: store, jobs: jobs, fetcher: fetcher, italian: true)
  }

  func lora(_ name: String) -> DTHubCatalogLoRA { DTHubCatalogLoRA(file: name.lowercased().replacingOccurrences(of: " ", with: "_") + ".ckpt", name: name) }

  func civitai(_ query: String, _ results: [(id: Int, name: String)]) {
    let items = results.map { #"{"id":\#($0.id),"name":"\#($0.name)","modelVersions":[{"baseModel":"Krea 2"}]}"# }.joined(separator: ",")
    fetcher.set(LACivitai.searchURL(query), text: #"{"items":[\#(items)]}"#)
    for result in results {
      fetcher.set(LACivitai.modelURL(result.id), text: #"{"description":"<p>Page \#(result.id)</p>","modelVersions":[{"id":1,"images":[]}]}"#)
    }
  }

  func huggingFace(_ query: String, _ repos: [String]) {
    fetcher.set(LAHuggingFace.searchURL(query), text: "[" + repos.map { #"{"id":"\#($0)","downloads":9}"# }.joined(separator: ",") + "]")
  }

  @Test func aNameIsAlsoSearchedWithoutItsFirstWord() async {
    let k2 = lora("K2 Giallostyle")
    civitai("K2 Giallostyle", [])
    civitai("Giallostyle", [(9, "Giallostyle"), (10, "Giallo from the movies")])
    await jobs.searchAll([k2])
    let entry = store.entry(for: k2.file)
    #expect(entry.link == "https://civitai.com/models/9" && entry.foundBySearch && entry.candidates.isEmpty)
    #expect(entry.notes == "Page 9")
  }

  @Test func withoutTheSameNameTheResultsAreKeptToChooseFrom() async {
    let pulp = lora("K2 Retropulp")
    civitai("K2 Retropulp", [(1, "Painted Retro Pulp Covers")])
    civitai("Retropulp", [(1, "Painted Retro Pulp Covers"), (2, "Boris Vallejo, retro pulp fantasy")])
    huggingFace("Retropulp", ["someone/retro-pulp-lora"])
    await jobs.searchAll([pulp])
    let entry = store.entry(for: pulp.file)
    #expect(entry.link == nil && entry.searched && !entry.foundBySearch)
    #expect(entry.candidates.map(\.link) == ["https://civitai.com/models/1", "https://civitai.com/models/2", "https://huggingface.co/someone/retro-pulp-lora"])
    #expect(entry.candidates[0].info == "Krea 2" && entry.candidates[2].downloads == 9)
    #expect(jobs.toSearch(in: [pulp]).isEmpty)
    // They are still there after a restart.
    #expect(LAStore(folder: folder).entry(for: pulp.file).candidates == entry.candidates)
  }

  @Test func atMostThreeFromCivitaiAndTwoFromHuggingFace() async {
    let many = lora("K2 Many")
    civitai("K2 Many", [])
    civitai("Many", (1...6).map { ($0, "Result \($0)") })
    huggingFace("Many", ["a/one", "b/two", "c/three"])
    await jobs.searchAll([many])
    #expect(store.entry(for: many.file).candidates.map(\.title) == ["Result 1", "Result 2", "Result 3", "a/one", "b/two"])
  }

  @Test func aRepositoryOfTheSameNameIsTakenFromHuggingFace() async {
    let consistency = lora("Flux2 Klein 9B Consistency v2")
    huggingFace("Klein 9B Consistency v2", ["dx8152/Klein-9B-Consistency", "copy/Klein-9B-Consistency"])
    await jobs.searchAll([consistency])
    let entry = store.entry(for: consistency.file)
    #expect(entry.link == "https://huggingface.co/dx8152/Klein-9B-Consistency" && entry.foundBySearch && entry.candidates.isEmpty)
  }

  @Test func nothingFoundAnywhereIsNotFound() async {
    let none = lora("K2 Nothing")
    await jobs.searchAll([none])
    #expect(store.entry(for: none.file) == LAEntry(searched: true))
  }

  @Test func aSiteAskingToSlowDownStopsTheSearchWhicheverItIs() async {
    let pulp = lora("K2 Retropulp")
    civitai("K2 Retropulp", [])
    civitai("Retropulp", [(1, "Painted Retro Pulp Covers")])
    fetcher.set(LAHuggingFace.searchURL("Retropulp"), .failure(.rateLimited))
    await jobs.searchAll([pulp])
    #expect(jobs.message == L.text(.rateLimited, italian: true))
    #expect(store.entry(for: pulp.file) == LAEntry() && jobs.toSearch(in: [pulp]) == [pulp])
  }

  @Test func aSiteThatDoesNotAnswerLeavesTheLoRAToSearch() async {
    let pulp = lora("K2 Retropulp")
    civitai("K2 Retropulp", [])
    fetcher.set(LACivitai.searchURL("Retropulp"), .failure(.unreachable))
    await jobs.searchAll([pulp])
    #expect(jobs.toSearch(in: [pulp]) == [pulp] && jobs.message == nil)
  }

  @Test func searchAgainForgetsTheOldCandidates() async {
    let pulp = lora("K2 Retropulp")
    civitai("Retropulp", [(1, "Painted Retro Pulp Covers")])
    await jobs.searchAll([pulp])
    #expect(store.entry(for: pulp.file).candidates.count == 1)
    civitai("Retropulp", [(3, "Retropulp")])
    await jobs.searchAgain(pulp)
    #expect(store.entry(for: pulp.file).link == "https://civitai.com/models/3" && store.entry(for: pulp.file).candidates.isEmpty)
  }

  @Test func choosingACandidateLinksAndImportsIt() async {
    let pulp = lora("K2 Retropulp")
    civitai("Retropulp", [(1, "Painted Retro Pulp Covers"), (2, "Boris")])
    await jobs.searchAll([pulp])
    let chosen = store.entry(for: pulp.file).candidates[1]
    await state.importPage(for: pulp.file, link: chosen.link, notes: .keepUsers)
    let entry = store.entry(for: pulp.file)
    #expect(entry.link == "https://civitai.com/models/2" && entry.candidates.isEmpty && !entry.foundBySearch)
    #expect(entry.notes == "Page 2" && entry.rawNotes)
  }

  @Test func candidatesOfAnotherShapeAreLeftOut() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let json = #"{"schema":1,"loras":{"a.ckpt":{"searched":true,"candidates":[{"title":"T","link":"https://civitai.com/models/1"},{"title":"no link"},7]}}}"#
    try Data(json.utf8).write(to: folder.appendingPathComponent("loras.json"))
    #expect(LAStore(folder: folder).entry(for: "a.ckpt").candidates == [LACandidate(title: "T", link: "https://civitai.com/models/1")])
  }
}
