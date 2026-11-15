import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class QwenInpaintingPlugin: DTHubPlugin {
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.qweninpainting", name: "Qwen 2.1 Inpainting", version: "1.3", symbol: "scribble.variable",
    families: ["qwen_image_2.1"], tools: QITools.declarations)
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
    case "tool.call":
      guard let call = DTHubToolCall(message), let host else { return DTHubMessage.bare("unsupported") }
      return await QITools.handle(call, state: state, connection: QITools.Connection(send: { [state] in await Self.sendDrawing(state, host) }))
    default:
      return DTHubMessage.bare("unsupported")
    }
  }

  private func send() {
    guard let host else { return }
    Task { await Self.sendDrawing(state, host) }
  }

  /// The Send button, from the tab and from a tool of an agent: the same work.
  private static func sendDrawing(_ state: InpaintingState, _ host: DTHubHost) async {
    await state.send(
      using: { text, images, system, model in
        await host.askLanguageModelAnswer(
          text, images: images, system: system, model: model, options: PromptEnhancer.options)
      },
      contribute: { await host.contribute($0) })
  }
}

@objc(QwenInpaintingEntry)
public final class QwenInpaintingEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { QwenInpaintingPlugin() }
}
