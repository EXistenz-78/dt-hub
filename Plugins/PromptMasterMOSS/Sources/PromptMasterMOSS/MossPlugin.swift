import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class MossPlugin: DTHubPlugin {
  /// Le famiglie del plug-in, in un solo punto: MOSS Image (Base e SFT) ha la `version` `mossImage` nell'elenco ufficiale
  /// dei modelli di Draw Things e `moss_image` nelle sue configurazioni; l'app non normalizza.
  static let families = ["moss_image", "mossImage"]

  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.promptmastermoss", name: "Prompt Master MOSS", version: "1.0", symbol: "wand.and.stars",
    families: MossPlugin.families)
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: Text(L.text(.title)))
  }

  func start(host: DTHubHost) { self.host = host }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context", "project", "activate", "deactivate":
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }
}

@objc(PromptMasterMOSSEntry)
public final class PromptMasterMOSSEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { MossPlugin() }
}
