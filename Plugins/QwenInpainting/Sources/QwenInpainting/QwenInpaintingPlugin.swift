import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class QwenInpaintingPlugin: DTHubPlugin {
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.qweninpainting", name: "Qwen 2.1 Inpainting", version: "1.0", symbol: "scribble.variable",
    families: ["qwen_image_2.1"])
  private let state = InpaintingState()
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: InpaintingView(state: state, send: { [weak self] in self?.send() }))
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
      // The marks and the texts belong to the open project.
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
        using: { text, images, system, model in
          await host.askLanguageModelAnswer(
            text, images: images, system: system, model: model, options: DTHubLLMOptions(maxTokens: 2048, thinking: false, timeout: 600))
        },
        contribute: { await host.contribute($0) })
    }
  }
}

@objc(QwenInpaintingEntry)
public final class QwenInpaintingEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { QwenInpaintingPlugin() }
}
