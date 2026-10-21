import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class TiledUpscalePlugin: DTHubPlugin {
  /// Edit and in-context models only: the tile is the picture the model changes. For now the plug-in has a preset for
  /// FLUX.2 klein 9B only (`TUPresetTable`).
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.tiledupscale", name: "Tiled Upscale", version: "1.1", symbol: "square.grid.3x3",
    families: nil, requiresEditModel: true)
  private let state = TUState(store: TUStore(folder: nil))
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    let actions = TUViewActions(
      prepare: { [weak self] confirmed in self?.prepare(confirmed: confirmed) },
      useAsStart: { [weak self] in self?.useAsStart() })
    return NSHostingController(rootView: TUView(state: state, actions: actions))
  }

  func start(host: DTHubHost) {
    self.host = host
    state.contribute = { await host.contribute($0) }
  }

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
    case "activate":
      state.active = true
      return nil
    case "deactivate":
      state.active = false
      return nil
    case "session.next":
      return await state.sessionNext(message)
    case "session.end":
      let object = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any]
      await state.sessionEnded(reason: object?["reason"] as? String ?? "closed")
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }

  private func prepare(confirmed: Bool) {
    guard let host else { return }
    Task {
      await state.prepare(
        confirmed: confirmed, contribute: { await host.contribute($0) },
        registerPreset: { await host.registerPresets([$0]) })
    }
  }

  private func useAsStart() {
    guard let host else { return }
    Task { await state.useAsStart(contribute: { await host.contribute($0) }) }
  }
}

@objc(TiledUpscaleEntry)
public final class TiledUpscaleEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { TiledUpscalePlugin() }
}
