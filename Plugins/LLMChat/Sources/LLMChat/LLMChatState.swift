import DTHubPluginKit
import Foundation

/// What the tab shows and does: the open chat, the project's chats, the settings, the draft, and the sending of a message.
@MainActor
final class LLMChatState: ObservableObject {
  /// The question to the LLM: prompt, picture paths, system prompt, model name, earlier turns.
  typealias Ask = @MainActor (String, [String], String, String, [DTHubLLMTurn]) async -> DTHubLLMAnswer
  /// `host.contribute`.
  typealias Contribute = @MainActor ([String: Any]) async -> [String: Any]?

  private var store: ChatStore
  private let italian: Bool
  /// Bumped when the answer being waited for must not land any more: another project, another chat, "stop waiting".
  private var generation = 0
  private var isRestoring = false

  @Published var context: DTHubContext?
  @Published var chat = Chat()
  @Published var summaries: [ChatSummary] = []
  @Published var settings = ChatSettings() {
    didSet { if !isRestoring { store.save(settings) } }
  }
  @Published var draft = ""
  @Published var isWaiting = false
  @Published var active = false

  init(store: ChatStore = ChatStore(folder: nil), italian: Bool = L.systemIsItalian) {
    self.store = store
    self.italian = italian
    open(initialFrom: store)
  }

  // MARK: What the app says

  func apply(context new: Data) {
    guard let decoded = try? JSONDecoder().decode(DTHubContext.self, from: new) else { return }
    context = decoded
  }

  /// The app opened a project: its chats and settings.
  func switchProject(folder: URL) {
    generation += 1
    isWaiting = false
    store = ChatStore(folder: folder)
    open(initialFrom: store)
  }

  private func open(initialFrom store: ChatStore) {
    isRestoring = true
    settings = store.loadSettings()
    isRestoring = false
    summaries = store.list()
    if let id = settings.currentChat, let saved = store.load(id) {
      chat = saved
    } else if let first = summaries.first, let saved = store.load(first.id) {
      chat = saved
    } else {
      chat = Chat()
    }
  }

  // MARK: Model, images, blocker

  var models: [DTHubLanguageModel] { context?.languageModels ?? [] }

  /// The model chosen by hand if it is still in the folder, else the first.
  var resolvedModel: DTHubLanguageModel? {
    models.first { $0.name == settings.model } ?? models.first
  }

  var imagesAvailable: Bool { resolvedModel?.supportsImages == true }

  /// Why messages cannot be sent now, in words; nil when they can.
  var blocker: String? {
    if !active { return L.text(.notActive, italian: italian) }
    guard let context else { return L.text(.waitingContext, italian: italian) }
    if context.prompt == nil { return L.text(.needsNewApp, italian: italian) }
    if models.isEmpty { return L.text(.noModels, italian: italian) }
    return nil
  }

  func selectModel(_ name: String) { settings.model = name }

  // MARK: Chats

  func newChat() {
    generation += 1
    isWaiting = false
    chat = Chat()
    settings.currentChat = chat.id
  }

  func open(_ id: UUID) {
    guard let saved = store.load(id) else { return }
    generation += 1
    isWaiting = false
    chat = saved
    settings.currentChat = id
  }

  func rename(_ title: String) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    chat.title = trimmed
    if !chat.messages.isEmpty { persist() }
  }

  /// Deletes the open chat and opens the most recent one left, or an empty one.
  func deleteCurrent() {
    generation += 1
    isWaiting = false
    store.delete(chat.id)
    summaries = store.list()
    if let first = summaries.first, let saved = store.load(first.id) {
      chat = saved
    } else {
      chat = Chat()
    }
    settings.currentChat = chat.id
  }

  /// Adds the command at the end of what is being written.
  func insertCommand() {
    let command = L.command(italian: italian)
    if !draft.isEmpty, !(draft.last?.isWhitespace ?? true) { draft += " " }
    draft += command
  }

  func cancelWait() {
    generation += 1
    isWaiting = false
  }

  private func persist() {
    chat.updated = Date()
    store.save(chat)
    summaries = store.list()
  }

  private func append(_ message: ChatMessage) {
    chat.messages.append(message)
    if chat.title.isEmpty, message.role == .user {
      chat.title = ChatTitle.make(from: message.text, date: message.date, italian: italian)
    }
    persist()
  }

  private func note(_ kind: ChatMessage.NoteKind, _ text: String) {
    append(ChatMessage(role: .note, text: text, note: kind))
  }

  // MARK: Sending

  /// Sends the draft as a message: the LLM answers, and with the command in the message its action block is sent to the app.
  func send(using ask: Ask, contribute: Contribute) async {
    guard blocker == nil, !isWaiting, let context, let model = resolvedModel else { return }
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    let gate = CommandGate.isOpen(text)

    // The pictures, only when the switch is on and the model reads them: the start image, then the Moodboard.
    var paths: [String] = []
    var hasStart = false
    if settings.includeImages, model.supportsImages {
      if let start = context.startImage {
        paths.append(start)
        hasStart = true
      }
      paths += context.moodboard ?? []
    }
    let block = ImageLabels.block(hasStart: hasStart, references: paths.count - (hasStart ? 1 : 0))
    let history = HistoryWindow.turns(of: chat.messages)
    let system = SystemPrompt.make(context: context)

    append(ChatMessage(role: .user, text: text, images: paths.map { ($0 as NSString).lastPathComponent }))
    if history.trimmed, !chat.messages.contains(where: { $0.note == .info && $0.text == L.text(.trimmed, italian: italian) }) {
      note(.info, L.text(.trimmed, italian: italian))
    }
    draft = ""
    isWaiting = true
    let mine = generation
    let answer = await ask((block ?? "") + text, paths, system, model.name, history.turns)
    guard generation == mine else { return }
    isWaiting = false

    switch answer {
    case .failure(let reason):
      note(.error, reason)
    case .text(let reply):
      append(ChatMessage(role: .assistant, text: reply))
      await handleActions(in: reply, gate: gate, contribute: contribute, generation: mine)
    }
  }

  private func handleActions(in reply: String, gate: Bool, contribute: Contribute, generation mine: Int) async {
    let json = ActionBlock.find(in: reply)
    guard gate else {
      if json != nil {
        note(.ignored, L.format(.ignoredNoCommand, L.command(italian: italian), italian: italian))
      }
      return
    }
    guard let json else {
      note(.ignored, L.text(.noAction, italian: italian))
      return
    }
    switch ActionBlock.body(from: json, italian: italian) {
    case .failure(.invalidJSON(let why)):
      note(.error, L.format(.invalidBlock, why, italian: italian))
    case .failure(.tooManySteps(let count)):
      note(.error, L.format(.tooManySteps, count, italian: italian))
    case .failure(.empty):
      note(.ignored, L.text(.nothingUsable, italian: italian))
    case .success(let body):
      let answer = await contribute(body)
      guard generation == mine else { return }
      let summary = ActionBlock.summary(of: body, answer: answer, italian: italian)
      note(summary.isError ? .error : .action, summary.text)
      if answer?["type"] as? String != "error", answer != nil { applyLocally(body) }
    }
  }

  /// What the tab holds now, as far as this plug-in knows: the new context arrives only at the next change of tab.
  private func applyLocally(_ body: [String: Any]) {
    guard var updated = context else { return }
    if let fields = body["fields"] as? [String: Any] {
      if let v = fields["prompt"] as? String { updated.prompt = v }
      if let v = fields["negativePrompt"] as? String { updated.negativePrompt = v }
      var p = updated.parameters ?? DTHubParameters.empty
      if let v = fields["width"] as? Int { p.width = v }
      if let v = fields["height"] as? Int { p.height = v }
      if let v = fields["steps"] as? Int { p.steps = v }
      if let v = (fields["guidanceScale"] as? NSNumber)?.doubleValue { p.guidanceScale = v }
      if let v = (fields["shift"] as? NSNumber)?.doubleValue { p.shift = v }
      if let v = fields["resolutionDependentShift"] as? Bool { p.resolutionDependentShift = v }
      if let v = fields["cfgZeroStar"] as? Bool { p.cfgZeroStar = v }
      if let v = fields["cfgZeroInitSteps"] as? Int { p.cfgZeroInitSteps = v }
      if let v = fields["seed"] as? Int { p.seed = UInt32(clamping: v) }
      if let v = fields["randomSeed"] as? Bool { p.randomSeed = v }
      if let v = fields["batchSize"] as? Int { p.batchSize = v }
      if let v = fields["batchCount"] as? Int { p.batchCount = v }
      if let name = fields["sampler"] as? String,
        let index = SamplerNames.names.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
      {
        p.sampler = index
      } else if let v = fields["sampler"] as? Int {
        p.sampler = v
      }
      updated.parameters = p
    }
    if let loras = body["loras"] as? [[String: Any]], var p = updated.parameters {
      for entry in loras {
        guard let file = entry["file"] as? String, let weight = (entry["weight"] as? NSNumber)?.doubleValue else { continue }
        if let index = p.loras?.firstIndex(where: { $0.file == file }) { p.loras?[index].weight = weight }
      }
      updated.parameters = p
    }
    if let strength = (body["strength"] as? NSNumber)?.doubleValue, updated.startImage != nil { updated.strength = min(1, max(0, strength)) }
    context = updated
  }
}

extension DTHubParameters {
  /// Parameters with nothing known yet (the kit only decodes them).
  static var empty: DTHubParameters {
    // swiftlint:disable:next force_try
    try! JSONDecoder().decode(DTHubParameters.self, from: Data("{}".utf8))
  }
}
