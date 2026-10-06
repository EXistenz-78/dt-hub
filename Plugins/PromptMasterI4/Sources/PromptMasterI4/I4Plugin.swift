import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class PromptMasterI4Plugin: DTHubPlugin {
  /// Its tab is grey on the other families: this plug-in writes the caption of Ideogram 4 only.
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.promptmasteri4", name: "Prompt Master I4", version: "1.0", symbol: "curlybraces",
    families: ["ideogram_4"])
  private let state = I4State()
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: I4View(state: state, send: { [weak self] in self?.send() }))
  }

  func start(host: DTHubHost) {
    self.host = host
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      state.update(generationSize: GenerationSize.read(fromContext: message))
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
    guard state.canSend, let host else { return }
    state.isSending = true
    state.status = ""
    let sender = I4Sender(contribute: { await host.contribute($0) }, italian: state.italian)
    let text = state.jsonText
    Task {
      let outcome = await sender.send(text)
      state.status = outcome.status
      state.isSending = false
    }
  }
}

@objc(PromptMasterI4Entry)
public final class PromptMasterI4Entry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { PromptMasterI4Plugin() }
}
