import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class Flux3EditingPlugin: DTHubPlugin {
  /// Le famiglie del plug-in, in un solo punto. Per ora FLUX.2 [klein] (come Prompt Master F3), così si prova nell'app fino
  /// alla generazione del prompt; quando Draw Things espone FLUX.3 Klein si aggiunge il suo id (sconosciuto: nessuna ipotesi).
  static let families = ["flux2_9b", "flux2_4b"]

  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.flux3editing", name: "Flux3 Editing", version: "1.0", symbol: "rectangle.on.rectangle",
    families: Flux3EditingPlugin.families)
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: Text(L.text(.title)).padding())
  }

  func start(host: DTHubHost) { self.host = host }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context", "project", "activate", "deactivate": return nil
    default: return DTHubMessage.bare("unsupported")
    }
  }
}

@objc(Flux3EditingEntry)
public final class Flux3EditingEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { Flux3EditingPlugin() }
}
