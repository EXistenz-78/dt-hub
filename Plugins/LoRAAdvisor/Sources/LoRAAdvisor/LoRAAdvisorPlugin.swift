import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class LoRAAdvisorPlugin: DTHubPlugin {
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.loraadvisor", name: "LoRA Advisor", version: "1.6.1", symbol: "square.stack.3d.down.right",
    families: nil, tools: LATools.declarations)
  private var host: DTHubHost?
  let state: LAState

  /// How the plug-in talks to the app: the jobs and the state both go through these two, so one place decides what
  /// "saved" means. The tests replace them.
  var sendSettings: (String, DTHubLoRASettings) async -> [String: Any]? = { _, _ in nil }
  var sendWeights: (String, Double?, Double?, Double?) async -> [String: Any]? = { _, _, _, _ in nil }

  /// The jobs are made before the state and the state needs them: they reach the plug-in through this box.
  private final class Link {
    weak var plugin: LoRAAdvisorPlugin?
  }

  /// An answer counts as a save only when it is there and is not an error.
  private static func isOK(_ answer: [String: Any]?) -> Bool {
    guard let answer else { return false }
    return answer["type"] as? String != "error"
  }

  convenience init() {
    // The master prompt, written to Data/LoRAAdvisor if missing or older (and custom/ made).
    LAPrompts.install()
    self.init(store: LAStore(folder: LAStore.defaultFolder), fetcher: LAFetcher(), summarise: nil)
  }

  /// `summarise` replaces the language model of the app (tests only).
  init(
    store: LAStore, fetcher: any LAFetching, summarise: ((String, String) async -> String?)?,
    pause: Duration = .milliseconds(500)
  ) {
    let asker = Asker()
    self.asker = asker
    let link = Link()
    let jobs = LAJobs(
      store: store, fetcher: fetcher, summarise: summarise ?? { system, prompt in await asker.text(system, prompt) },
      pause: pause,
      saveSettings: { file, settings in await Self.isOK(link.plugin?.sendSettings(file, settings)) },
      saveWeights: { file, low, base, high in await Self.isOK(link.plugin?.sendWeights(file, low, base, high)) },
      catalog: { MainActor.assumeIsolated { link.plugin?.state.catalog ?? [] } })
    state = LAState(store: store, jobs: jobs, fetcher: fetcher)
    link.plugin = self
    sendSettings = { [weak self] file, settings in await self?.host?.setLoRASettings(file: file, settings) }
    sendWeights = { [weak self] file, low, base, high in
      await self?.host?.setLoRAWeights(file: file, min: low, base: base, max: high)
    }
    state.saveSettings = { [weak self] file, settings in await self?.sendSettings(file, settings) }
    state.saveWeights = { [weak self] file, low, base, high in await self?.sendWeights(file, low, base, high) }
  }

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: LAView(state: state))
  }

  func start(host: DTHubHost) {
    self.host = host
    asker.host = host
    state.contribute = { [weak self] body in await self?.host?.contribute(body) }
    state.askModel = { [weak self] system, prompt in await self?.asker.answer(system, prompt) ?? .failure("No answer.") }
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      state.apply(context: message)
      return nil
    case "activate":
      state.active = true
      return nil
    case "deactivate":
      state.active = false
      return nil
    case "tool.call":
      guard let call = DTHubToolCall(message) else { return DTHubMessage.failure("Not a tool call.") }
      return await LATools.handle(call, state: state)
    case "project":
      // The notes and thumbnails are about the LoRAs, not about a project: one state for all, by choice.
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }

  /// Asks the app's language model (the one the user assigned to plug-ins), without its thinking.
  private let asker: Asker

  @MainActor
  private final class Asker {
    var host: DTHubHost?

    private var options: DTHubLLMOptions {
      var options = DTHubLLMOptions()
      options.thinking = false
      options.maxTokens = 800
      return options
    }

    func answer(_ system: String, _ prompt: String) async -> DTHubLLMAnswer {
      guard let host else { return .failure("No answer.") }
      return await host.askLanguageModelAnswer(prompt, system: system, options: options)
    }

    func text(_ system: String, _ prompt: String) async -> String? {
      if case .text(let text) = await answer(system, prompt) { return text }
      return nil
    }
  }
}

@objc(LoRAAdvisorEntry)
public final class LoRAAdvisorEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { LoRAAdvisorPlugin() }
}
