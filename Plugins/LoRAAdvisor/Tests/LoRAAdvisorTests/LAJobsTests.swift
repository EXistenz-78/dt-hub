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
    // The run ended there: the next LoRA was not asked for.
    #expect(!searches.contains(LACivitai.searchURL("Delta").absoluteString))
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
    store.update("a.ckpt") { $0.analysed = true }
    #expect(jobs.toSummarise(in: catalog) == [c])
    await jobs.summariseAll(catalog)
    #expect(llm.calls.count == 1)
    #expect(store.entry(for: "c.ckpt").notes == "Riassunto breve." && !store.entry(for: "c.ckpt").rawNotes)
    #expect(store.pageText(for: "c.ckpt") == nil && jobs.message == nil)
    // A plain-text answer is a summary but not an analysis: only an analysis marks the LoRA as seen.
    store.update("c.ckpt") { $0.analysed = true }
    await jobs.summariseAll(catalog)
    #expect(llm.calls.count == 1)
  }

  @Test func aFailedSummaryLeavesTheEntryRaw() async {
    serveBoth()
    await jobs.searchAll(catalog)
    store.update("a.ckpt") { $0.analysed = true }
    llm.answer = { _ in nil }
    await jobs.summariseAll(catalog)
    #expect(store.entry(for: "c.ckpt").rawNotes && jobs.toSummarise(in: catalog) == [c])
    #expect(jobs.message == L.text(.summaryFailed, italian: true))
    llm.answer = { _ in "  \n" }
    #expect(await jobs.summarise(c) == false)
    #expect(store.entry(for: "c.ckpt").notes == "Page of Gamma Ray")
  }

  @Test func notesEditedByHandLeaveTheRound() async {
    serveBoth()
    await jobs.searchAll(catalog)
    store.setNotesByUser("corrette da me", for: "c.ckpt")
    store.update("a.ckpt") { $0.analysed = true }
    store.update("c.ckpt") { $0.analysed = true }
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

  // MARK: The analysis

  let json = #"{"summary":"Stile acquarello.","category":"turbo","weight":{"min":0.6,"base":0.8,"max":1},"turbo":{"steps":8,"guidance":1.5,"shift":3},"triggers":["zap"]}"#

  /// A jobs object with the closures that save and the catalog the app has now.
  final class Saved: @unchecked Sendable {
    var settings: [(String, DTHubLoRASettings)] = []
    var weights: [(String, Double?, Double?, Double?)] = []
    var settingsOK = true
    var catalog: [DTHubCatalogLoRA] = []
  }

  func analysing(_ saved: Saved) -> LAJobs {
    let llm = llm
    return LAJobs(
      store: store, fetcher: fetcher, summarise: { await llm.ask($0, $1) }, pause: .zero, italian: true,
      saveSettings: { file, settings in
        saved.settings.append((file, settings))
        return saved.settingsOK
      },
      saveWeights: { file, low, base, high in
        saved.weights.append((file, low, base, high))
        return true
      },
      catalog: { saved.catalog })
  }

  @Test func aRawLoRAGetsNotesAndFields() async {
    serveBoth()
    await jobs.searchAll(catalog)
    let saved = Saved()
    saved.catalog = catalog
    llm.answer = { [json] _ in json }
    let jobs = analysing(saved)
    #expect(jobs.toSummarise(in: catalog).contains(c))
    await jobs.summariseAll([c])
    let entry = store.entry(for: "c.ckpt")
    #expect(entry.notes == "Stile acquarello." && !entry.rawNotes && entry.analysed && entry.triggerProposal == "zap")
    #expect(store.pageText(for: "c.ckpt") == nil && jobs.message == nil)
    #expect(saved.settings.count == 1 && saved.settings[0].0 == "c.ckpt")
    #expect(saved.settings[0].1 == DTHubLoRASettings(category: .set("turbo"), steps: .set(8), guidance: .set(1.5), shift: .set(3)))
    #expect(saved.weights.count == 1 && saved.weights[0].1 == 0.6 && saved.weights[0].2 == 0.8 && saved.weights[0].3 == 1)
  }

  @Test func anAlreadySummarisedLoRARefetchesAndKeepsItsNotes() async {
    serve("Alpha", results: [])
    fetcher.set(
      LACivitai.modelURL(1), text: #"{"description":"<p>Page of Alpha</p>","modelVersions":[{"id":1,"images":[]}]}"#)
    store.setNotesByUser("mie note", for: "a.ckpt")
    let saved = Saved()
    saved.catalog = catalog
    llm.answer = { [json] _ in json }
    let jobs = analysing(saved)
    #expect(jobs.toSummarise(in: catalog) == [a])
    await jobs.summariseAll(catalog)
    #expect(fetcher.requests.filter { $0.contains("/models/1") }.count == 1)
    let entry = store.entry(for: "a.ckpt")
    #expect(entry.notes == "mie note" && !entry.rawNotes && entry.analysed)
    #expect(store.pageText(for: "a.ckpt") == nil)
    #expect(saved.settings.count == 1 && saved.weights.count == 1)
    #expect(jobs.toSummarise(in: catalog).isEmpty)
  }

  @Test func aSummaryOnlyAnswerKeepsTheOldBehaviour() async {
    serveBoth()
    await jobs.searchAll(catalog)
    let saved = Saved()
    saved.catalog = catalog
    llm.answer = { _ in "  «Un riassunto semplice.»  " }
    let jobs = analysing(saved)
    await jobs.summariseAll([c])
    let entry = store.entry(for: "c.ckpt")
    #expect(entry.notes == "Un riassunto semplice." && !entry.rawNotes && !entry.analysed)
    #expect(saved.settings.isEmpty && saved.weights.isEmpty)
  }

  @Test func brokenJSONCountsAsFailed() async {
    serveBoth()
    await jobs.searchAll(catalog)
    let saved = Saved()
    saved.catalog = catalog
    llm.answer = { _ in "{ not json" }
    let jobs = analysing(saved)
    await jobs.summariseAll([c])
    #expect(store.entry(for: "c.ckpt").rawNotes && !store.entry(for: "c.ckpt").analysed)
    #expect(jobs.message == L.text(.summaryFailed, italian: true))
  }

  @Test func aFailedSaveDoesNotStopTheProposal() async {
    serveBoth()
    await jobs.searchAll(catalog)
    let saved = Saved()
    saved.catalog = catalog
    saved.settingsOK = false
    llm.answer = { [json] _ in json }
    let jobs = analysing(saved)
    await jobs.summariseAll([c])
    let entry = store.entry(for: "c.ckpt")
    #expect(entry.triggerProposal == "zap" && entry.analysed && jobs.message == nil)
  }

  @Test func anUnreachablePageSkipsThatLoRAOnly() async {
    serveBoth()
    await jobs.searchAll(catalog)
    store.setNotesByUser("mie", for: "a.ckpt")
    fetcher.set(LACivitai.modelURL(1), .failure(.unreachable))
    let saved = Saved()
    saved.catalog = catalog
    llm.answer = { [json] _ in json }
    let jobs = analysing(saved)
    await jobs.summariseAll([a, c])
    #expect(!store.entry(for: "a.ckpt").analysed && store.entry(for: "a.ckpt").notes == "mie")
    #expect(store.entry(for: "c.ckpt").analysed)
    #expect(jobs.message == L.text(.summaryFailed, italian: true))
  }

  @Test func aLoRAThatLeftTheCatalogIsSkipped() async {
    serveBoth()
    await jobs.searchAll(catalog)
    let saved = Saved()
    saved.catalog = [a, b, d]
    llm.answer = { [json] _ in json }
    let jobs = analysing(saved)
    await jobs.summariseAll([c])
    let entry = store.entry(for: "c.ckpt")
    #expect(entry.rawNotes && !entry.analysed && saved.settings.isEmpty && saved.weights.isEmpty)
  }

  @Test func aTriggerTypedMeanwhileMeansNoProposal() async {
    serveBoth()
    await jobs.searchAll(catalog)
    let saved = Saved()
    saved.catalog = [a, b, DTHubCatalogLoRA(file: "c.ckpt", name: "Gamma Ray v1.0", trigger: "Zap"), d]
    llm.answer = { [json] _ in json }
    let jobs = analysing(saved)
    await jobs.summariseAll([c])
    #expect(store.entry(for: "c.ckpt").triggerProposal == nil && store.entry(for: "c.ckpt").analysed)
  }
}
