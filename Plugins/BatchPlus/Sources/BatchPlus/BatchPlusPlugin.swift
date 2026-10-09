import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class BatchPlusPlugin: DTHubPlugin {
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.batchplus", name: "Batch plus", version: "1.0", symbol: "square.stack.3d.up", families: nil)
  private var host: DTHubHost?

  func makeViewController() -> NSViewController { NSHostingController(rootView: Text("Batch plus")) }
  func start(host: DTHubHost) { self.host = host }
  func handle(_ message: Data) async -> Data? { DTHubMessage.bare("unsupported") }
}

@objc(BatchPlusEntry)
public final class BatchPlusEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { BatchPlusPlugin() }
}
