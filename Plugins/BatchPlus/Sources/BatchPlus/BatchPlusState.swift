import DTHubPluginKit
import Foundation

/// What the tab shows and edits: the remembered session (per project), the parameters the app last sent, and what is
/// being sent.
@MainActor
final class BatchPlusState: ObservableObject {
  private var store: BatchPlusStore
  /// True while a project's state is being read into the tab: the changes that causes are not written back.
  private var isRestoring = false

  @Published var session: BatchPlusSession {
    didSet {
      // Only when something is in excess: writing `session` here runs this observer again.
      if session.samplers.count > session.samplerLimit { session.trimSamplers() }
      persist()
    }
  }
  /// The Generation tab's parameters from the last `context`; nil before the first one, or from an app that does
  /// not send them.
  @Published var parameters: DTHubParameters?
  @Published var modelName: String?
  @Published var contextArrived = false
  @Published var active = false
  @Published var status = ""
  @Published var isSending = false

  init(store: BatchPlusStore = BatchPlusStore()) {
    self.store = store
    session = store.load() ?? .initial()
  }

  /// The `context` message: the model and the parameters as they are now.
  func apply(context data: Data) {
    guard let context = try? JSONDecoder().decode(DTHubContext.self, from: data) else { return }
    modelName = context.model
    parameters = context.parameters
    contextArrived = true
  }

  /// The app opened a project: its state, or the initial one (`adoptLegacy`: the first project ever takes the state the
  /// tab had before projects).
  func switchProject(folder: URL, adoptLegacy: Bool) {
    store.folder = folder
    if adoptLegacy { store.adoptLegacy() }
    isRestoring = true
    session = store.load() ?? .initial()
    isRestoring = false
  }

  private func persist() {
    guard !isRestoring else { return }
    store.save(session)
  }

  // MARK: What the series would be

  /// The values the series starts from, from the tab's parameters.
  var base: BatchBase? {
    guard let p = parameters else { return nil }
    return BatchBase(
      steps: p.steps, guidanceScale: p.guidanceScale, shift: p.shift, cfgZeroInitSteps: p.cfgZeroInitSteps, seed: p.seed, sampler: p.sampler,
      loras: (p.loras ?? []).map { BatchBase.LoRA(file: $0.file, weight: $0.weight) })
  }

  var shiftIsAuto: Bool { parameters?.resolutionDependentShift == true }
  var resolved: (batch: ParameterBatch, invalid: Set<String>) { session.batch(shiftIsAuto: shiftIsAuto) }
  /// The seed of the shuffle: the preview shows what will be sent, and a new one is drawn after each send, when the switch
  /// changes and on "shuffle again".
  @Published private(set) var shuffleSeed = UInt64.random(in: 0...UInt64.max)

  func reshuffle() { shuffleSeed = UInt64.random(in: 0...UInt64.max) }

  /// The prompts the text makes, one per pass (one only when the text has no list, and then it cannot be sent).
  var promptItems: [String] {
    PromptTemplate.prompts(from: session.promptText, shuffle: session.shuffle, seed: shuffleSeed)
  }

  /// How many passes the prompt text makes (0 without a list).
  var promptPasses: Int { PromptTemplate.lists(session.promptText).isEmpty ? 0 : PromptTemplate.passCount(session.promptText) }

  /// Why the button is off, in words; nil when the series can go.
  func blocker(italian: Bool = L.systemIsItalian) -> String? {
    switch session.mode {
    case .parameters:
      guard base != nil else { return L.text(contextArrived ? .needsNewApp : .noParameters, italian: italian) }
      let (batch, invalid) = resolved
      if !invalid.isEmpty { return L.text(.invalidIncrement, italian: italian) }
      if batch.increments.isEmpty && batch.loraIncrements.isEmpty && batch.samplers.isEmpty { return L.text(.noIncrements, italian: italian) }
      return nil
    case .prompts:
      return promptPasses < 2 ? L.text(.promptsFew, italian: italian) : nil
    }
  }

  /// The `pipeline` to send, or nil when `blocker` says no.
  func pipeline(italian: Bool = L.systemIsItalian) -> [String: Any]? {
    guard blocker(italian: italian) == nil else { return nil }
    switch session.mode {
    case .parameters:
      guard let base else { return nil }
      return BatchPlusBuilder.pipeline(resolved.batch, from: base, italian: italian)
    case .prompts:
      return BatchPlusBuilder.pipeline(
        prompts: promptItems, fixedSeed: session.fixedSeed, seed: parameters?.seed, italian: italian)
    }
  }

  /// The line under the button for the app's answer to `contribute`.
  static func describe(_ answer: [String: Any]?, italian: Bool) -> String {
    guard let answer else { return L.text(.notAnswered, italian: italian) }
    if answer["type"] as? String == "error" { return answer["text"] as? String ?? L.text(.notAnswered, italian: italian) }
    let conflicts = answer["conflicts"] as? Int ?? 0
    return conflicts > 0 ? L.format(.sentWithConflicts, conflicts, italian: italian) : L.text(.sent, italian: italian)
  }
}
