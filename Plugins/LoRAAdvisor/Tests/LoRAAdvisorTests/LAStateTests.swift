import DTHubPluginKit
import Foundation
import Testing

@testable import LoRAAdvisor

@MainActor
struct LAStateTests {
  let store = LAStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("la-state-\(UUID().uuidString)", isDirectory: true))
  let fetcher = FakeFetcher()
  let state: LAState

  init() {
    let jobs = LAJobs(store: store, fetcher: fetcher, summarise: { _, _ in nil }, pause: .zero, italian: true)
    state = LAState(store: store, jobs: jobs, fetcher: fetcher, italian: true)
  }

  static let four = """
    [{"file":"a.ckpt","name":"Alpha","family":"b","trigger":"aa","weight":0.8},
     {"file":"p.ckpt","name":"Piu luce","family":"b","trigger":"","weight":1},
     {"file":"z.ckpt","name":"Zeta","family":"a","trigger":"","weight":1},
     {"file":"u.ckpt","name":"Unknown","trigger":"","weight":1}]
    """

  func context(
    catalog: String? = LAStateTests.four, family: String? = "b", model: String = "m.ckpt", prompt: String = "un prompt",
    loras: String = "[]", models: String = #"[{"name":"llm","path":"/x","supportsImages":false}]"#, startImage: String? = nil
  ) -> Data {
    var parts = [
      #""type":"context""#, #""tempFolder":"/tmp/x""#, #""model":"\#(model)""#, #""prompt":"\#(prompt)""#,
      #""parameters":{"loras":\#(loras)}"#, #""languageModels":\#(models)"#,
    ]
    if let family { parts.append(#""family":"\#(family)""#) }
    if let catalog { parts.append(#""loraCatalog":\#(catalog)"#) }
    if let startImage { parts.append(#""startImage":"\#(startImage)""#) }
    return Data(("{" + parts.joined(separator: ",") + "}").utf8)
  }

  @Test func theListSaysWhyItIsEmpty() {
    #expect(state.blocker == .notActive)
    state.active = true
    #expect(state.blocker == nil)
    state.apply(context: context(catalog: nil))
    #expect(state.blocker == .oldApp)
    state.apply(context: context(catalog: "[]"))
    #expect(state.blocker == .noLoRAs)
    state.apply(context: context())
    #expect(state.blocker == nil)
  }

  /// A server parked to make room for the language model lists no LoRAs for a while: the list and the advice stay.
  @Test func anEmptyCatalogDoesNotWipeAListThatWasThere() {
    state.apply(context: context())
    state.setAdvice(#"[{"n":1}]"#, candidates: state.candidates())
    state.apply(context: context(catalog: "[]"))
    #expect(state.catalog.count == 4 && state.blocker == nil)
    #expect(state.suggestions.count == 1)
  }

  @Test func theCurrentFamilyComesFirstAndUnknownLast() {
    state.apply(context: context())
    #expect(state.groups.map(\.family) == ["b", "a", nil])
    #expect(state.groups.map(\.isCurrent) == [true, false, false])
    #expect(state.groups[0].loras.map(\.name) == ["Alpha", "Piu luce"])
  }

  // MARK: Min, Base and Max

  @Test func theWeightsAreNormalisedAndSentToTheApp() async {
    state.apply(context: context())
    var sent: [(String, Double?, Double?, Double?)] = []
    state.saveWeights = { file, low, base, high in
      sent.append((file, low, base, high))
      return ["type": "ok"]
    }
    await state.setWeights(min: 0.5, base: 2, max: 1.2, for: "a.ckpt")
    #expect(sent.count == 1 && sent[0].1 == 0.5 && sent[0].2 == 1.2 && sent[0].3 == 1.2)
    let lora = state.catalog.first { $0.file == "a.ckpt" }
    #expect(lora?.minWeight == 0.5 && lora?.weight == 1.2 && lora?.maxWeight == 1.2)
    await state.setWeights(min: 0.5, base: 2, max: 1.2, for: "a.ckpt")  // nothing changed: nothing sent
    #expect(sent.count == 1 && state.weightsMessage == nil)
    await state.setWeights(min: nil, base: nil, max: nil, for: "a.ckpt")
    #expect(sent.count == 2 && sent[1].1 == nil && sent[1].2 == 1 && sent[1].3 == nil)
  }

  @Test func anAppThatDoesNotAnswerLeavesAMessage() async {
    state.apply(context: context())
    state.saveWeights = { _, _, _, _ in nil }
    await state.setWeights(min: 0.1, base: nil, max: nil, for: "a.ckpt")
    #expect(state.weightsMessage == state.text(.weightsNotSaved))
  }

  @Test func theWeightsOfTheCatalogComeFromTheContext() {
    state.apply(context: context(catalog: #"[{"file":"a.ckpt","name":"A","family":"b","weight":0.8,"minWeight":0.4,"maxWeight":1.1}]"#))
    #expect(LAWeights.values(of: state.catalog[0]) == LAWeights.Values(min: 0.4, base: 0.8, max: 1.1))
  }

  @Test func theAdviceStaysWithinTheLimitsOfEachLoRA() {
    state.apply(context: context(catalog: #"[{"file":"a.ckpt","name":"A","family":"b","maxWeight":0.7},{"file":"p.ckpt","name":"P","family":"b","minWeight":0.5}]"#))
    state.setAdvice(#"[{"n":1,"weight":1.4},{"n":2,"weight":0.1}]"#, candidates: state.candidates())
    #expect(state.suggestions.map(\.weight) == [0.7, 0.5])
  }

  @Test func typedWeightsAreReadWithCommaOrPoint() {
    #expect(LAWeights.parse("0,75") == 0.75 && LAWeights.parse(" 1.2 ") == 1.2)
    #expect(LAWeights.parse("") == nil && LAWeights.parse("abc") == nil)
    #expect(LAWeights.parse(LAWeights.format(0.75)) == 0.75 && LAWeights.format(nil) == "")
  }

  // MARK: Collapsible families

  private func open(_ state: LAState) -> [String?] { state.groups.filter { state.isOpen($0) }.map(\.family) }

  @Test func onlyTheCurrentFamilyStartsOpen() {
    state.apply(context: context())
    #expect(open(state) == ["b"])
  }

  @Test func aFamilyOpensAndClosesByHand() {
    state.apply(context: context())
    state.toggle(state.groups[1])
    #expect(open(state) == ["b", "a"])
    state.toggle(state.groups[0])
    #expect(open(state) == ["a"])
    state.toggle(state.groups[2])
    #expect(open(state) == ["a", nil])
  }

  @Test func aNewModelOpensItsFamilyAndLeavesTheRestAlone() {
    state.apply(context: context())
    state.toggle(state.groups[0])  // the user closes "b"
    state.apply(context: context(family: "b", prompt: "altro"))  // same model: nothing opens again
    #expect(open(state).isEmpty)
    state.apply(context: context(family: "a", model: "n.ckpt"))
    #expect(open(state) == ["a"])
    state.apply(context: context(family: "b", model: "m.ckpt"))
    #expect(open(state) == ["b", "a"])
  }

  @Test func aSearchShowsTheResultsInClosedFamilies() {
    state.apply(context: context())
    state.filter = "zeta"
    #expect(state.groups.map(\.family) == ["a"])
    #expect(open(state) == ["a"])
    state.toggle(state.groups[0])  // ignored while searching
    #expect(open(state) == ["a"])
    state.filter = ""
    #expect(open(state) == ["b"])  // and the family stayed closed
  }

  @Test func thePreviewFollowsTheOpenRow() {
    state.apply(context: context())
    #expect(state.openLoRA == nil)
    state.openFile = "z.ckpt"
    #expect(state.openLoRA?.name == "Zeta")
    state.openFile = "gone.ckpt"
    #expect(state.openLoRA == nil)
  }

  @Test func theFilterLooksAtNameTriggerAndNotes() {
    state.apply(context: context())
    store.setNotesByUser("grana da pellicola", for: "z.ckpt")
    state.filter = "PELL"
    #expect(state.groups.map(\.family) == ["a"] && state.groups[0].loras.map(\.name) == ["Zeta"])
    state.filter = "più"
    #expect(state.groups.flatMap(\.loras).map(\.name) == ["Piu luce"])
    state.filter = "aa"
    #expect(state.groups.flatMap(\.loras).map(\.name) == ["Alpha"])
    state.filter = "nulla di simile"
    #expect(state.groups.isEmpty)
  }

  @Test func addIsOffForAnotherFamily() {
    state.apply(context: context())
    let byName = Dictionary(uniqueKeysWithValues: state.catalog.map { ($0.name, $0) })
    #expect(state.canAdd(byName["Alpha"]!) && state.canAdd(byName["Unknown"]!))
    #expect(!state.canAdd(byName["Zeta"]!))
  }

  @Test func aLoRAOnTheTabIsKnown() {
    state.apply(context: context(loras: #"[{"file":"a.ckpt","weight":1,"mode":0,"trigger":""}]"#))
    #expect(state.isOnTab("a.ckpt") && !state.isOnTab("p.ckpt"))
  }

  @Test func theRequestFollowsThePromptUntilEdited() {
    state.apply(context: context(prompt: "uno"))
    #expect(state.request == "uno")
    state.apply(context: context(prompt: "due"))
    #expect(state.request == "due")
    state.editRequest("pellicola anni 80")
    state.apply(context: context(prompt: "tre"))
    #expect(state.request == "pellicola anni 80")
    state.resetRequest()
    #expect(state.request == "tre")
    state.apply(context: context(prompt: "quattro"))
    #expect(state.request == "quattro")
  }

  @Test func adviceStates() {
    state.apply(context: context())
    let candidates = state.candidates()
    #expect(candidates.map(\.lora.name) == ["Alpha", "Piu luce"])
    state.setAdvice("non so", candidates: candidates)
    #expect(state.adviceMessage == L.text(.adviceNotUnderstood, italian: true) && state.suggestions.isEmpty)
    state.setAdvice("[]", candidates: candidates)
    #expect(state.adviceMessage == L.text(.noSuitable, italian: true))
    state.setAdvice(#"[{"n":2,"weight":0.6,"why":"luce"}]"#, candidates: candidates)
    #expect(state.suggestions == [LAAdvice.Suggestion(file: "p.ckpt", weight: 0.6, why: "luce")] && state.adviceMessage == nil)
  }

  @Test func aSuggestionForALoRAThatLeftTheCatalogIsDropped() {
    state.apply(context: context())
    state.setAdvice(#"[{"n":1},{"n":2}]"#, candidates: state.candidates())
    #expect(state.suggestions.count == 2)
    state.apply(context: context(catalog: #"[{"file":"a.ckpt","name":"Alpha","family":"b","trigger":"aa","weight":0.8}]"#))
    #expect(state.suggestions.map(\.file) == ["a.ckpt"])
  }

  @Test func suggestionsGoWhenTheModelChanges() {
    state.apply(context: context())
    state.setAdvice(#"[{"n":1}]"#, candidates: state.candidates())
    state.apply(context: context(model: "other.ckpt"))
    #expect(state.suggestions.isEmpty)
  }

  @Test func adviceNeedsALanguageModelAndCandidates() {
    state.apply(context: context(models: "[]"))
    #expect(!state.hasLanguageModel)
    state.apply(context: context(family: "none"))
    #expect(state.hasLanguageModel && state.candidates().isEmpty)
  }

  @Test func adviseAsksTheModelAndReadsItsAnswer() async {
    state.apply(context: context(prompt: "ritratto"))
    nonisolated(unsafe) var asked: (system: String, prompt: String)?
    state.askModel = { system, prompt in
      asked = (system, prompt)
      return .text(#"[{"n":1,"weight":0.7,"why":"serve"}]"#)
    }
    await state.advise()
    #expect(asked?.prompt.contains("ritratto") == true && asked?.prompt.contains("1. Alpha | aa | -") == true)
    #expect(state.suggestions == [LAAdvice.Suggestion(file: "a.ckpt", weight: 0.7, why: "serve")])
    state.askModel = { _, _ in .failure("Nessun modello.") }
    await state.advise()
    #expect(state.suggestions.isEmpty && state.adviceMessage == "Nessun modello.")
  }

  @Test func addSendsTheLoRAWithItsWeightAndTrigger() async throws {
    state.apply(context: context())
    nonisolated(unsafe) var sent: [[String: Any]] = []
    state.contribute = { body in
      sent.append(body)
      return ["type": "ok", "conflicts": 0]
    }
    let alpha = state.catalog[0]
    await state.add(alpha)
    let lora = try #require((sent.first?["loras"] as? [[String: Any]])?.first)
    #expect(lora["file"] as? String == "a.ckpt" && lora["weight"] as? Double == 0.8 && lora["trigger"] as? String == "aa")
    #expect(state.status == L.text(.sent, italian: true))
    // A LoRA of another family is never sent.
    await state.add(state.catalog[2])
    #expect(sent.count == 1)
    state.contribute = { _ in nil }
    await state.add(alpha, weight: 0.5)
    #expect(state.status == L.text(.notAnswered, italian: true))
  }

  @Test func notesTypedByTheUserAreSavedAndEndTheRawState() {
    state.apply(context: context())
    store.update("a.ckpt") {
      $0.notes = "raw"
      $0.rawNotes = true
    }
    // Showing the notes as they are changes nothing.
    state.setNotes("raw", for: "a.ckpt")
    state.flushNotes()
    #expect(store.entry(for: "a.ckpt").rawNotes)
    state.setNotes("mie", for: "a.ckpt")
    #expect(state.notes(for: "a.ckpt") == "mie")
    state.flushNotes()
    #expect(store.entry(for: "a.ckpt").notes == "mie" && !store.entry(for: "a.ckpt").rawNotes)
  }

  @Test func aLinkThatIsNotAPageIsRefusedWithoutARequest() async {
    state.apply(context: context())
    await state.importPage(for: "a.ckpt", link: "https://example.com/x", notes: .keepUsers)
    #expect(state.rowMessage(for: "a.ckpt") == L.text(.linkNotRecognised, italian: true))
    #expect(fetcher.requests.isEmpty && store.entry(for: "a.ckpt").link == nil)
  }

  @Test func importingFromALinkTheUserGaveIsNotASearchResult() async {
    state.apply(context: context())
    store.update("a.ckpt") {
      $0.link = "https://civitai.com/models/1"
      $0.foundBySearch = true
    }
    fetcher.set(LACivitai.modelURL(7), text: #"{"description":"<p>Testo</p>","modelVersions":[{"id":1,"images":[]}]}"#)
    #expect(state.needsConfirmationToImport("a.ckpt") == false)
    await state.importPage(for: "a.ckpt", link: " https://civitai.red/models/7/slug ", notes: .keepUsers)
    let entry = store.entry(for: "a.ckpt")
    #expect(entry.link == "https://civitai.com/models/7" && !entry.foundBySearch && entry.notes == "Testo")
    #expect(state.rowMessage(for: "a.ckpt") == L.text(.noImageInPage, italian: true))
    store.setNotesByUser("mie", for: "a.ckpt")
    #expect(state.needsConfirmationToImport("a.ckpt"))
    fetcher.set(LACivitai.modelURL(7), .failure(.needsAccess))
    await state.importPage(for: "a.ckpt", link: "https://civitai.com/models/7", notes: .replace)
    #expect(state.rowMessage(for: "a.ckpt") == L.text(.needsAccess, italian: true) && store.entry(for: "a.ckpt").notes == "mie")
  }

  @Test func aPictureDroppedOnARowIsTheUsersThumbnail() {
    state.apply(context: context())
    #expect(state.setThumbnail(fromData: Data("no".utf8), for: "a.ckpt") == false)
    #expect(state.rowMessage(for: "a.ckpt") == L.text(.unreadableImage, italian: true))
    #expect(state.setThumbnail(fromData: Pictures.png(), for: "a.ckpt"))
    #expect(store.entry(for: "a.ckpt").manualThumbnail && state.rowMessage(for: "a.ckpt") == nil)
    state.dropHadNoPicture(for: "p.ckpt")
    #expect(state.rowMessage(for: "p.ckpt") == L.text(.dropOnlyAddress, italian: true))
  }

  @Test func aThumbnailFromAFileIsTheUsers() throws {
    state.apply(context: context())
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("la-pics-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let good = folder.appendingPathComponent("a.png")
    let bad = folder.appendingPathComponent("b.png")
    try Pictures.png().write(to: good)
    try Data("no".utf8).write(to: bad)
    #expect(state.setThumbnail(fromFile: bad, for: "a.ckpt") == false)
    #expect(state.rowMessage(for: "a.ckpt") == L.text(.unreadableImage, italian: true) && store.entry(for: "a.ckpt").thumbnail == nil)
    #expect(state.setThumbnail(fromFile: good, for: "a.ckpt"))
    #expect(store.entry(for: "a.ckpt").manualThumbnail && state.rowMessage(for: "a.ckpt") == nil)
    state.removeThumbnail(for: "a.ckpt")
    #expect(store.entry(for: "a.ckpt").thumbnail == nil)
    state.apply(context: context(startImage: good.path))
    #expect(state.canUseControlImage && state.useControlImage(for: "a.ckpt"))
    #expect(store.entry(for: "a.ckpt").manualThumbnail)
  }
}
