import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class QwenInpaintingPlugin: DTHubPlugin {
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.qweninpainting", name: "Qwen 2.1 Inpainting", version: "1.0", symbol: "scribble.variable",
    families: ["qwen_image_2.1"])
  private var host: DTHubHost?

  func makeViewController() -> NSViewController { NSHostingController(rootView: Text("Qwen 2.1 Inpainting")) }
  func start(host: DTHubHost) { self.host = host }
  func handle(_ message: Data) async -> Data? { DTHubMessage.bare("unsupported") }
}

@objc(QwenInpaintingEntry)
public final class QwenInpaintingEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { QwenInpaintingPlugin() }
}
