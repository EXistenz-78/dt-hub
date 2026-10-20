import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class F3Plugin: DTHubPlugin {
  /// Le famiglie del plug-in, in un solo punto. Per ora FLUX.2 [klein] (le stesse di Sphere Light), così si prova nell'app
  /// fino alla generazione del prompt; quando Draw Things espone FLUX.3 Klein si aggiunge il suo id.
  static let families = ["flux2_9b", "flux2_4b"]

  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.promptmasterf3", name: "Prompt Master F3", version: "1.0", symbol: "curlybraces.square",
    families: F3Plugin.families)
  private var host: DTHubHost?

  func makeViewController() -> NSViewController { NSHostingController(rootView: Text("Prompt Master F3")) }

  func start(host: DTHubHost) { self.host = host }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context", "project", "activate", "deactivate": return nil
    default: return DTHubMessage.bare("unsupported")
    }
  }
}

@objc(PromptMasterF3Entry)
public final class PromptMasterF3Entry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { F3Plugin() }
}
