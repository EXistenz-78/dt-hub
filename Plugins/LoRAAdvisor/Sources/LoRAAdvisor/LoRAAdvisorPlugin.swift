import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class LoRAAdvisorPlugin: DTHubPlugin {
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.loraadvisor", name: "LoRA Advisor", version: "1.2", symbol: "square.stack.3d.down.right",
    families: nil)
  private var host: DTHubHost?
  private let state: LAState

  init() {
    let store = LAStore(folder: LAStore.defaultFolder)
    let fetcher = LAFetcher()
    let asker = Asker()
    self.asker = asker
    let jobs = LAJobs(store: store, fetcher: fetcher, summarise: { system, prompt in await asker.text(system, prompt) })
    state = LAState(store: store, jobs: jobs, fetcher: fetcher)
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
