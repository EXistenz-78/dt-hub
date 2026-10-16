import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class DepthPosePlugin: DTHubPlugin {
  /// All the families: the maps are plain pictures any model can take as a reference.
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.depthpose", name: "Depth & Pose", version: "1.0", symbol: "figure.stand", families: nil)
  private let state = DPState(
    store: DPStore(), models: DPModelStore(), detector: VisionPoseDetector(),
    makeDepth: { url in DepthEstimator(model: try CoreMLDepthModel(compiledModel: url)) })
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    let actions = DPViewActions(
      create: { [weak self] in
        guard let self else { return }
        Task { await self.state.create() }
      },
      send: { [weak self] in self?.send() },
      download: { [weak self] in
        guard let self else { return }
        Task { await self.state.downloadModel() }
      },
      cancel: { [weak self] in self?.state.cancelDownload() })
    return NSHostingController(rootView: DPView(state: state, actions: actions))
  }

  func start(host: DTHubHost) {
    self.host = host
    Task { await state.prepare() }
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      state.apply(context: message)
      return nil
    case "project":
      // The choice of maps belongs to the open project.
      if let project = try? JSONDecoder().decode(DTHubProject.self, from: message) {
        state.switchProject(folder: URL(fileURLWithPath: project.folder, isDirectory: true), adoptLegacy: project.adoptLegacy)
      }
      return nil
    case "activate":
      state.active = true
      return nil
    case "deactivate":
      state.active = false
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }

  private func send() {
    guard let host else { return }
    Task { await state.send { await host.contribute($0) } }
  }
}

@objc(DepthPoseEntry)
public final class DepthPoseEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { DepthPosePlugin() }
}
