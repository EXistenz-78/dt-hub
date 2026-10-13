import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class LoRAAdvisorPlugin: DTHubPlugin {
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.loraadvisor", name: "LoRA Advisor", version: "1.0", symbol: "square.stack.3d.down.right",
    families: nil)
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: Text(verbatim: "LoRA Advisor"))
  }

  func start(host: DTHubHost) {
    self.host = host
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context", "activate", "deactivate":
      return nil
    case "project":
      // The notes and thumbnails are about the LoRAs, not about a project: one state for all, by choice.
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }
}

@objc(LoRAAdvisorEntry)
public final class LoRAAdvisorEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { LoRAAdvisorPlugin() }
}
