import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class LLMChatPlugin: DTHubPlugin {
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.llmchat", name: "LLM Chat", version: "1.0", symbol: "bubble.left.and.text.bubble.right",
    families: nil)
  private var host: DTHubHost?

  func makeViewController() -> NSViewController { NSHostingController(rootView: Text("LLM Chat")) }
  func start(host: DTHubHost) { self.host = host }
  func handle(_ message: Data) async -> Data? { DTHubMessage.bare("unsupported") }
}

@objc(LLMChatEntry)
public final class LLMChatEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { LLMChatPlugin() }
}
