import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class DepthPosePlugin: DTHubPlugin {
  /// All the families: the maps are plain pictures any model can take as a reference.
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.depthpose", name: "Depth & Pose", version: "1.0", symbol: "figure.stand", families: nil)
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: Text("Depth & Pose"))
  }

  func start(host: DTHubHost) {
    self.host = host
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context", "project", "activate", "deactivate":
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }
}

@objc(DepthPoseEntry)
public final class DepthPoseEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { DepthPosePlugin() }
}
