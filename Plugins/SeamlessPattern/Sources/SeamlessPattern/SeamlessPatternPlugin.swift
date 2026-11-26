import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class SeamlessPatternPlugin: DTHubPlugin {
  /// The families the custom server tiles (the same list as `SeamlessTile.families` in the app: the plug-in does not
  /// depend on HubKit). On any other family the plug-in is switched off and its tab is hidden.
  static let families = ["krea_2", "z_image", "flux2_9b", "flux2_4b", "flux3_5b"]
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.seamlesspattern", name: "Seamless Pattern", version: "1.0", symbol: "square.split.2x2.fill",
    families: SeamlessPatternPlugin.families, tools: SPTools.declarations)
  private let state = SPState()
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: SPTabView(state: state))
  }

  func start(host: DTHubHost) {
    self.host = host
    state.send = { data in
      guard let body = SPSender.body(data) else { return nil }
      return await host.contribute(body)
    }
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) {
        await state.applyContext(
          family: context.family, customServer: context.customServer, lastResultPath: context.lastResult?.path)
      }
      return nil
    case "project":
      // The mode and the view belong to the open project.
      if let project = try? JSONDecoder().decode(DTHubProject.self, from: message) {
        state.switchProject(folder: URL(fileURLWithPath: project.folder, isDirectory: true))
      }
      return nil
    case "activate":
      state.active = true
      return nil
    case "deactivate":
      // The app takes the plug-in's pipeline back when it is switched off: nothing to send.
      state.active = false
      state.deactivate()
      return nil
    case "tool.call":
      guard let call = DTHubToolCall(message) else { return DTHubMessage.bare("unsupported") }
      return await SPTools.handle(call, state: state, connection: SPTools.Connection())
    default:
      return DTHubMessage.bare("unsupported")
    }
  }
}

@objc(SeamlessPatternEntry)
public final class SeamlessPatternEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { SeamlessPatternPlugin() }
}
