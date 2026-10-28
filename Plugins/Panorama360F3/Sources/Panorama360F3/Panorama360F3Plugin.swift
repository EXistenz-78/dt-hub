import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class Panorama360F3Plugin: DTHubPlugin {
  /// FLUX.3 [klein] 5.6B: the «360» and «Seamfix» LoRAs of this plug-in are trained on it.
  static let families = ["flux3_5b"]

  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.panorama360f3", name: "Pano 360 F3", version: "1.0", symbol: "globe",
    families: Panorama360F3Plugin.families)

  init() {}

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: Text(verbatim: "Pano 360 F3"))
  }

  func start(host: DTHubHost) {}

  func handle(_ message: Data) async -> Data? {
    DTHubMessage.bare("unsupported")
  }
}

@objc(Panorama360F3Entry)
public final class Panorama360F3Entry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { Panorama360F3Plugin() }
}
