import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class AIAssistantPlugin: DTHubPlugin {
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.llmchat", name: "AI Assistant", version: "1.0", symbol: "bubble.left.and.text.bubble.right",
    families: nil)
  private let state = AIAssistantState()
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: AIAssistantView(state: state, send: { [weak self] in self?.send() }))
  }

  func start(host: DTHubHost) {
    self.host = host
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      state.apply(context: message)
      return nil
    case "project":
      // The chats belong to the open project.
      if let project = try? JSONDecoder().decode(DTHubProject.self, from: message) {
        state.switchProject(folder: URL(fileURLWithPath: project.folder, isDirectory: true))
      }
      return nil
    case "activate":
      state.active = true
      return nil
    case "deactivate":
      state.active = false
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }

  private func send() {
    guard let host else { return }
    Task {
      await state.send(
        using: { prompt, images, system, model, history in
          await host.askLanguageModelAnswer(
            prompt, images: images, system: system, model: model,
            options: DTHubLLMOptions(maxTokens: 4096, timeout: 600), history: history)
        },
        contribute: { await host.contribute($0) })
    }
  }
}

@objc(AIAssistantEntry)
public final class AIAssistantEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { AIAssistantPlugin() }
}
