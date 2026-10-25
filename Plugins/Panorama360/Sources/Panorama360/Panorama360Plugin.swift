import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class Panorama360Plugin: DTHubPlugin {
  /// FLUX.2 [klein] 9B and 4B (the «360 ERP outpaint» LoRA exists only for FLUX.2).
  static let families = ["flux2_9b", "flux2_4b"]

  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.panorama360", name: "Panorama 360", version: "1.0", symbol: "globe",
    families: Panorama360Plugin.families)
  private let state = PSState()
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: PSView(state: state))
  }

  func start(host: DTHubHost) { self.host = host }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      state.apply(context: message)
      return nil
    case "project":
      if let project = try? JSONDecoder().decode(DTHubProject.self, from: message) {
        state.switchProject(folder: URL(fileURLWithPath: project.folder, isDirectory: true))
      }
      return nil
    case "activate", "deactivate": return nil
    default: return DTHubMessage.bare("unsupported")
    }
  }
}

@objc(Panorama360Entry)
public final class Panorama360Entry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { Panorama360Plugin() }
}
