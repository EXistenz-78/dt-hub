import Combine
import DTHubPluginKit
import Foundation

/// What the tab shows and does: the list of the LoRAs with their notes and thumbnails, and the advice of the language
/// model. The notes and thumbnails are in `LAStore`; the app's side (the catalog, the prompt) comes with the context.
@MainActor
final class LAState: ObservableObject {
  let store: LAStore
  let jobs: LAJobs
  private let fetcher: any LAFetching
  private let italian: Bool

  @Published private(set) var context: DTHubContext?
  /// On for the job (header menu): only then the app sends the context and takes what the plug-in adds.
  @Published var active = false
  @Published var filter = ""
  /// The row that is open; one at a time.
  @Published var openFile: String? {
    didSet { if oldValue != openFile { flushNotes() } }
  }
  /// What to advise on: the prompt of the Generation tab until the user writes something else.
  @Published private(set) var request = ""
  private(set) var requestEditedByUser = false
  @Published private(set) var suggestions: [LAAdvice.Suggestion] = []
  @Published private(set) var adviceMessage: String?
  @Published private(set) var isAdvising = false
  /// The line at the bottom of the tab: what happened to the last "Add".
  @Published private(set) var status: String?
  /// The LoRA whose page is being imported from its row.
  @Published private(set) var importing: String?
  @Published private var rowMessages: [String: String] = [:]
  @Published private var draft: (file: String, text: String)?

  /// Set by the plug-in, which has the host: `contribute` puts LoRAs on the Generation tab, `askModel` asks the
  /// language model (system prompt, prompt).
  var contribute: (([String: Any]) async -> [String: Any]?)?
  var askModel: ((String, String) async -> DTHubLLMAnswer)?

  private var saveNotes: Task<Void, Never>?
  private var importTask: Task<Void, Never>?
  private var watching: AnyCancellable?

  init(store: LAStore, jobs: LAJobs, fetcher: any LAFetching, italian: Bool = L.systemIsItalian) {
    self.store = store
    self.jobs = jobs
    self.fetcher = fetcher
    self.italian = italian
    // The jobs change the store as they go: the list follows their progress.
    watching = jobs.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
  }

  func text(_ key: L.Key) -> String { L.text(key, italian: italian) }

  // MARK: The context

  func apply(context data: Data) {
    guard let new = try? JSONDecoder().decode(DTHubContext.self, from: data) else { return }
    let modelChanged = context != nil && context?.model != new.model
    context = new
    if !requestEditedByUser { request = new.prompt ?? "" }
    if modelChanged {
      suggestions = []
      adviceMessage = nil
    } else {
      // A LoRA that left the server cannot be added any more.
      let files = Set(catalog.map(\.file))
      if suggestions.contains(where: { !files.contains($0.file) }) { suggestions.removeAll { !files.contains($0.file) } }
    }
  }

  var catalog: [DTHubCatalogLoRA] { context?.loraCatalog ?? [] }

  enum Blocker: Equatable {
    /// The plug-in is not on for the job, so the app never told it anything.
    case notActive
    /// An app before 0.2.2: no `loraCatalog`.
    case oldApp
    case noLoRAs
  }

  /// Why the list is empty; nil when it is not (or while the first context is on its way).
  var blocker: Blocker? {
    guard let context else { return active ? nil : .notActive }
    guard let catalog = context.loraCatalog else { return .oldApp }
    return catalog.isEmpty ? .noLoRAs : nil
  }

  struct Group: Equatable {
    /// Nil gathers the LoRAs whose family the server does not say.
    var family: String?
    var isCurrent: Bool
    var loras: [DTHubCatalogLoRA]
  }

  /// The LoRAs the filter keeps, by family: the current model's first, then the others by name, the unknown one last.
  var groups: [Group] {
    let wanted = Self.folded(filter.trimmingCharacters(in: .whitespacesAndNewlines))
    let shown = catalog.filter { lora in
      wanted.isEmpty
        || [lora.name, lora.trigger, notes(for: lora.file)].contains { Self.folded($0).contains(wanted) }
    }
    let current = context?.family
    let families = Set(shown.compactMap(\.family)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    var order: [String?] = families.filter { $0 == current } + families.filter { $0 != current }
    if shown.contains(where: { $0.family == nil }) { order.append(nil) }
    return order.map { family in
      Group(family: family, isCurrent: family != nil && family == current, loras: shown.filter { $0.family == family })
    }
  }

  /// The name of the current model's family, as the app's guide calls it when it has one.
  var familyLabel: String { context?.promptGuide?.label ?? context?.family ?? "—" }

  func entry(for file: String) -> LAEntry { store.entry(for: file) }
  func thumbnailURL(for file: String) -> URL? { store.thumbnailURL(for: file) }

  // MARK: Adding to the Generation tab

  /// LoRAs of different families cannot be mixed: only those of the current model's family, or of an unknown one.
  func canAdd(_ lora: DTHubCatalogLoRA) -> Bool {
    guard let family = lora.family else { return true }
    return family == context?.family
  }

  func isOnTab(_ file: String) -> Bool { context?.parameters?.loras?.contains { $0.file == file } ?? false }

  func add(_ lora: DTHubCatalogLoRA, weight: Double? = nil) async {
    guard canAdd(lora), let contribute else { return }
    report(await contribute(LAAdvice.contribution(lora, weight: weight)))
  }

  /// "Add all": every suggestion, with the weight shown on its card.
  func addAll() async {
    guard let contribute else { return }
    let loras = suggestions.compactMap { suggestion in
      catalog.first { $0.file == suggestion.file }.flatMap { lora in
        (LAAdvice.contribution(lora, weight: suggestion.weight)["loras"] as? [[String: Any]])?.first
      }
    }
    guard !loras.isEmpty else { return }
    report(await contribute(["loras": loras]))
  }

  private func report(_ answer: [String: Any]?) {
    guard let answer else {
      status = text(.notAnswered)
      return
    }
    if answer["type"] as? String == "error" {
      status = answer["text"] as? String ?? text(.notAnswered)
      return
    }
    let conflicts = answer["conflicts"] as? Int ?? 0
    status = conflicts > 0 ? L.text(.sentWithConflicts, conflicts, italian: italian) : text(.sent)
  }

  // MARK: The notes

  /// The notes as the row shows them: what is being typed, or what is saved.
  func notes(for file: String) -> String {
    if let draft, draft.file == file { return draft.text }
    return store.entry(for: file).notes
  }

  /// The user typed in the notes: saved half a second after the last key, and when the row closes.
  func setNotes(_ text: String, for file: String) {
    guard text != notes(for: file) else { return }
    if let draft, draft.file != file { flushNotes() }
    draft = (file, text)
    saveNotes?.cancel()
    saveNotes = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      self?.flushNotes()
    }
  }

  func flushNotes() {
    saveNotes?.cancel()
    saveNotes = nil
    guard let draft else { return }
    self.draft = nil
    if draft.text != store.entry(for: draft.file).notes { store.setNotesByUser(draft.text, for: draft.file) }
  }

  // MARK: Pages

  /// True while something of the tab is using the network or the language model: one thing at a time.
  var isBusy: Bool { jobs.running != nil || importing != nil || isAdvising }

  func rowMessage(for file: String) -> String? { rowMessages[file] }

  /// "Import from the page" would replace notes the user wrote: ask first.
  func needsConfirmationToImport(_ file: String) -> Bool {
    let entry = store.entry(for: file)
    return !notes(for: file).isEmpty && !entry.rawNotes
  }

  /// "Import from the page" on a row, with the link in its field.
  func importPage(for file: String, link text: String, notes: LAImporter.Notes) async {
    guard !isBusy else { return }
    flushNotes()
    guard let link = LALink.parse(text) else {
      rowMessages[file] = self.text(.linkNotRecognised)
      return
    }
    importing = file
    rowMessages[file] = nil
    // A link the user gave is theirs, whatever the search had found.
    store.update(file) { $0.foundBySearch = false }
    let outcome = await LAImporter(fetcher: fetcher, store: store).importPage(link, for: file, notes: notes)
    importing = nil
    guard !Task.isCancelled else { return }
    switch outcome {
    case .imported(let noImage): rowMessages[file] = noImage ? self.text(.noImageInPage) : nil
    case .failed(let error): rowMessages[file] = message(for: error)
    }
  }

  /// Starts the import of a row so that "Cancel" can end it.
  func startImport(for file: String, link: String, notes: LAImporter.Notes) {
    importTask = Task { await importPage(for: file, link: link, notes: notes) }
  }

  func cancelImport() {
    importTask?.cancel()
    importTask = nil
    importing = nil
  }

  private func message(for error: LAFetchError) -> String {
    switch error {
    case .notFound: text(.notFound)
    case .needsAccess: text(.needsAccess)
    case .rateLimited: text(.rateLimited)
    case .unreachable: text(.unreachable)
    case .tooLarge: text(.tooLarge)
    case .notAllowed: text(.notAllowed)
    case .unreadable: text(.unreadableAnswer)
    }
  }

  func notThisOne(_ file: String) {
    flushNotes()
    jobs.notThisOne(file)
    rowMessages[file] = nil
    objectWillChange.send()
  }

  func summarise(_ lora: DTHubCatalogLoRA) async {
    flushNotes()
    rowMessages[lora.file] = await jobs.summarise(lora) ? nil : text(.summaryFailed)
  }

  // MARK: Thumbnails

  /// A picture the user chose becomes the thumbnail; false when the file is not a picture.
  @discardableResult
  func setThumbnail(fromFile url: URL, for file: String) -> Bool {
    guard let data = try? Data(contentsOf: url), let jpeg = LAThumbnail.jpeg(from: data) else {
      rowMessages[file] = text(.unreadableImage)
      return false
    }
    store.setThumbnail(jpeg, manual: true, for: file)
    rowMessages[file] = nil
    objectWillChange.send()
    return true
  }

  var canUseControlImage: Bool { context?.startImage?.isEmpty == false }

  @discardableResult
  func useControlImage(for file: String) -> Bool {
    guard let path = context?.startImage, !path.isEmpty else { return false }
    return setThumbnail(fromFile: URL(fileURLWithPath: path), for: file)
  }

  func removeThumbnail(for file: String) {
    store.setThumbnail(nil, manual: false, for: file)
    objectWillChange.send()
  }

  // MARK: The advice

  var hasLanguageModel: Bool { context?.languageModels?.isEmpty == false }

  func editRequest(_ text: String) {
    guard text != request else { return }
    request = text
    requestEditedByUser = true
  }

  /// Back to the prompt of the Generation tab, which the field follows again.
  func resetRequest() {
    requestEditedByUser = false
    request = context?.prompt ?? ""
  }

  /// The LoRAs the language model chooses among: those of the current model's family.
  func candidates() -> [LAAdvice.Candidate] {
    LAAdvice.candidates(
      catalog: catalog, family: context?.family, notes: Dictionary(uniqueKeysWithValues: catalog.map { ($0.file, notes(for: $0.file)) }),
      request: request)
  }

  func advise() async {
    guard !isBusy, let askModel else { return }
    let candidates = candidates()
    guard !candidates.isEmpty else { return }
    flushNotes()
    isAdvising = true
    suggestions = []
    adviceMessage = nil
    let answer = await askModel(
      LAAdvice.system(italian: italian),
      LAAdvice.prompt(request: request, guide: context?.promptGuide?.label, candidates: candidates))
    isAdvising = false
    switch answer {
    case .text(let text): setAdvice(text, candidates: candidates)
    case .failure(let reason):
      suggestions = []
      adviceMessage = reason
    }
  }

  /// The answer of the language model, read against the list it was given.
  func setAdvice(_ answer: String, candidates: [LAAdvice.Candidate]) {
    guard let read = LAAdvice.parse(answer, candidates: candidates) else {
      suggestions = []
      adviceMessage = text(.adviceNotUnderstood)
      return
    }
    suggestions = read
    adviceMessage = read.isEmpty ? text(.noSuitable) : nil
  }

  /// The weight typed on a suggestion's card.
  func setWeight(_ weight: Double, forSuggestion file: String) {
    guard let index = suggestions.firstIndex(where: { $0.file == file }) else { return }
    suggestions[index].weight = LAAdvice.clamped(weight)
  }

  private static func folded(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }
}
