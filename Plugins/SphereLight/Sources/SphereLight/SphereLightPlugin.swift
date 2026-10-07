import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class SphereLightPlugin: DTHubPlugin {
  /// The families the plug-in works with: the whole FLUX.2 [klein] family. The sun-direction LoRA is made for the 9B and
  /// gives its best results there; it works on the 4B too. On the other families the plug-in is switched off and its tab
  /// is hidden.
  static let families = ["flux2_9b", "flux2_4b"]
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.spherelight", name: "Sphere Light", version: "1.0", symbol: "lightbulb.max",
    families: SphereLightPlugin.families)
  private let state = SLRState()
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: SphereLightView(state: state, send: { [weak self] kind in self?.send(kind) }))
  }

  func start(host: DTHubHost) {
    self.host = host
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) { state.tempFolder = context.tempFolder }
      return nil
    case "activate":
      state.active = true
      // The app only listens to a plug-in that is on: the presets are offered now. A name the menu has is never touched.
      _ = await host?.registerPresets(SLRMessages.presets())
      return nil
    case "deactivate":
      state.active = false
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }

  private func send(_ kind: SphereSender.Kind) {
    guard !state.isSending, let host else { return }
    state.isSending = true
    state.status = L.text(.rendering)
    let sender = SphereSender(
      contribute: { await host.contribute($0) }, registerPresets: { await host.registerPresets($0) })
    let (lights, overcast, saveToDesktop, folder) = (state.lights, state.overcast, state.saveToDesktop, state.tempFolder)
    Task {
      state.status = await sender.send(kind, lights: lights, overcast: overcast, saveToDesktop: saveToDesktop, tempFolder: folder)
      state.isSending = false
    }
  }
}

@objc(SphereLightEntry)
public final class SphereLightEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { SphereLightPlugin() }
}
