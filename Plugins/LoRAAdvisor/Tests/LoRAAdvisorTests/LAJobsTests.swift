import Foundation
import DTHubPluginKit
import Testing

@testable import LoRAAdvisor

/// Stands in for the language model: remembers what it was asked and answers from a closure.
final class FakeLLM: @unchecked Sendable {
  private let lock = NSLock()
  private var asked: [(system: String, prompt: String)] = []
  var answer: @Sendable (String) -> String? = { _ in "Riassunto breve." }
  var calls: [(system: String, prompt: String)] { lock.withLock { asked } }
  func ask(_ system: String, _ prompt: String) async -> String? {
    lock.withLock { asked.append((system, prompt)) }
    return answer(prompt)
  }
}

@MainActor
struct LAJobsTests {
  let store = LAStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("la-jobs-\(UUID().uuidString)", isDirectory: true))
  let fetcher = FakeFetcher()
  let llm = FakeLLM()
  let jobs: LAJobs

  let a = DTHubCatalogLoRA(file: "a.ckpt", name: "Alpha")
  let b = DTHubCatalogLoRA(file: "b.ckpt", name: "Beta")
  let c = DTHubCatalogLoRA(file: "c.ckpt", name: "Gamma Ray v1.0")
  let d = DTHubCatalogLoRA(file: "d.ckpt", name: "Delta")
  var catalog: [DTHubCatalogLoRA] { [a, b, c, d] }

  init() {
    let llm = llm
    jobs = LAJobs(store: store, fetcher: fetcher, summarise: { await llm.ask($0, $1) }, pause: .zero, italian: true)
    store.update("a.ckpt") { $0.link = "https://civitai.com/models/1" }
    store.update("b.ckpt") { $0.searched = true }
  }

  /// The search for a name answers with these models; the page of a model found is served too.
  func serve(_ name: String, results: [(id: Int, name: String)]) {
    let items = results.map { #"{"id":\#($0.id),"name":"\#($0.name)"}"# }.joined(separator: ",")
    fetcher.set(LACivitai.searchURL(name), text: #"{"items":[\#(items)]}"#)
    for result in results {
      fetcher.set(
        LACivitai.modelURL(result.id),
        text: #"{"description":"<p>Page of \#(result.name)</p>","modelVersions":[{"id":1,"images":[{"type":"image","url":"https://image.civitai.com/\#(result.id).jpeg"}]}]}"#)
      fetcher.set(URL(string: "https://image.civitai.com/\(result.id).jpeg")!, .success(Pictures.png()))
    }
  }

  func serveBoth() {
    serve("Gamma Ray v1.0", results: [(5, "Gamma"), (6, "Gamma Ray")])
    serve("Delta", results: [])
  }

  var searches: [String] { fetcher.requests.filter { $0.contains("/models?query=") } }

  @Test func searchesOnlyLoRAsWithoutALinkThatWereNeverSearched() {
    #expect(jobs.toSearch(in: catalog) == [c, d])
  }

  @Test func aMatchIsLinkedAndImported() async {
    serveBoth()
    await jobs.searchAll(catalog)
    let found = store.entry(for: "c.ckpt")
    #expect(found.link == "https://civitai.com/models/6" && found.foundBySearch && found.searched)
    #expect(found.notes == "Page of Gamma Ray" && found.rawNotes && found.thumbnail != nil)
    #expect(store.entry(for: "d.ckpt") == LAEntry(searched: true))
    #expect(jobs.running == nil && jobs.progress == nil && jobs.message == nil)
  }

  @Test func runningAgainSearchesNothing() async {
    serveBoth()
    await jobs.searchAll(catalog)
    let before = fetcher.requests.count
    await jobs.searchAll(catalog)
    #expect(fetcher.requests.count == before)
    #expect(jobs.toSearch(in: catalog).isEmpty)
  }

  @Test func aNewLoRAIsTheOnlyOneSearched() async {
    serveBoth()
    await jobs.searchAll(catalog)
    let e = DTHubCatalogLoRA(file: "e.ckpt", name: "Epsilon")
    serve("Epsilon", results: [])
    let before = searches.count
    await jobs.searchAll(catalog + [e])
    #expect(searches.count == before + 1 && searches.last == LACivitai.searchURL("Epsilon").absoluteString)
  }

  @Test func rateLimitStopsAndKeepsTheRestToDo() async {
    fetcher.set(LACivitai.searchURL("Gamma Ray v1.0"), .failure(.rateLimited))
    serve("Delta", results: [])
    await jobs.searchAll(catalog)
    #expect(jobs.message == L.text(.rateLimited, italian: true))
    #expect(jobs.toSearch(in: catalog) == [c, d])
    #expect(searches.count == 1)
  }

  @Test func stopLeavesTheRestToDo() async {
    serveBoth()
    let jobs = jobs
    fetcher.onRequest = { if $0.contains("/models?query=") { jobs.stop() } }
    await jobs.searchAll(catalog)
    #expect(store.entry(for: "c.ckpt").searched)
    #expect(jobs.toSearch(in: catalog) == [d])
    fetcher.onRequest = nil
    await jobs.searchAll(catalog)
    #expect(jobs.toSearch(in: catalog).isEmpty)
  }

  @Test func aNetworkErrorOnOneLoRADoesNotMarkIt() async {
    fetcher.set(LACivitai.searchURL("Gamma Ray v1.0"), .failure(.unreachable))
    serve("Delta", results: [])
    await jobs.searchAll(catalog)
    #expect(jobs.toSearch(in: catalog) == [c])
    #expect(store.entry(for: "d.ckpt").searched)
  }

  @Test func usersNotesSurviveTheSearch() async {
    serveBoth()
    store.setNotesByUser("mie", for: "c.ckpt")
    await jobs.searchAll(catalog)
    let found = store.entry(for: "c.ckpt")
    #expect(found.notes == "mie" && !found.rawNotes && found.link != nil)
  }

  @Test func aLoRAWithoutANameIsSearchedByItsFile() async {
    let nameless = DTHubCatalogLoRA(file: "gamma_ray_lora_f16.ckpt", name: "gamma_ray_lora_f16.ckpt")
    serve("gamma ray", results: [(6, "Gamma Ray")])
    await jobs.searchAll([nameless])
    #expect(store.entry(for: nameless.file).link == "https://civitai.com/models/6")
  }

  @Test func summarisesOnlyRawNotes() async {
    serveBoth()
    await jobs.searchAll(catalog)
    store.setNotesByUser("mie", for: "a.ckpt")
    #expect(jobs.toSummarise(in: catalog) == [c])
    await jobs.summariseAll(catalog)
    #expect(llm.calls.count == 1)
    #expect(store.entry(for: "c.ckpt").notes == "Riassunto breve." && !store.entry(for: "c.ckpt").rawNotes)
    #expect(store.pageText(for: "c.ckpt") == nil)
    await jobs.summariseAll(catalog)
    #expect(llm.calls.count == 1)
  }

  @Test func aFailedSummaryLeavesTheEntryRaw() async {
    serveBoth()
    await jobs.searchAll(catalog)
    llm.answer = { _ in nil }
    await jobs.summariseAll(catalog)
    #expect(store.entry(for: "c.ckpt").rawNotes && jobs.toSummarise(in: catalog) == [c])
    llm.answer = { _ in "  \n" }
    #expect(await jobs.summarise(c) == false)
    #expect(store.entry(for: "c.ckpt").notes == "Page of Gamma Ray")
  }

  @Test func notesEditedByHandLeaveTheRound() async {
    serveBoth()
    await jobs.searchAll(catalog)
    store.setNotesByUser("corrette da me", for: "c.ckpt")
    #expect(jobs.toSummarise(in: catalog).isEmpty)
    await jobs.summariseAll(catalog)
    #expect(llm.calls.isEmpty && store.entry(for: "c.ckpt").notes == "corrette da me")
  }

  @Test func thePageTextGoesInsideTheDelimitedBlock() async {
    serveBoth()
    await jobs.searchAll(catalog)
    await jobs.summariseAll(catalog)
    let call = llm.calls[0]
    #expect(call.prompt.contains("<page>\nPage of Gamma Ray\n</page>"))
    #expect(call.system.contains("<page>") && call.system.lowercased().contains("ignor"))
    #expect(call.system.contains("60") && call.system.contains("italiano"))
  }

  @Test func theAnswerIsCleaned() {
    #expect(LASummary.clean("  \"Un riassunto.\"\n") == "Un riassunto.")
    #expect(LASummary.clean("«Un riassunto.»") == "Un riassunto.")
    #expect(LASummary.clean(" \n ") == nil)
  }

  @Test func notThisOneClearsWhatTheSearchBrought() async {
    serveBoth()
    await jobs.searchAll(catalog)
    jobs.notThisOne("c.ckpt")
    #expect(store.entry(for: "c.ckpt") == LAEntry(searched: true))
    #expect(store.pageText(for: "c.ckpt") == nil)
    #expect(jobs.toSearch(in: catalog).isEmpty)
  }

  @Test func notThisOneKeepsWhatIsTheUsers() async {
    serveBoth()
    await jobs.searchAll(catalog)
    store.setNotesByUser("mie", for: "c.ckpt")
    store.setThumbnail(Data([9]), manual: true, for: "c.ckpt")
    jobs.notThisOne("c.ckpt")
    let entry = store.entry(for: "c.ckpt")
    #expect(entry.link == nil && !entry.foundBySearch && entry.searched)
    #expect(entry.notes == "mie" && entry.thumbnail != nil && entry.manualThumbnail)
  }

  @Test func searchAgainRetriesOneLoRA() async {
    serveBoth()
    await jobs.searchAll(catalog)
    serve("Delta", results: [(8, "delta")])
    let before = searches.count
    await jobs.searchAgain(d)
    #expect(searches.count == before + 1)
    #expect(store.entry(for: "d.ckpt").link == "https://civitai.com/models/8" && store.entry(for: "d.ckpt").foundBySearch)
  }
}
