import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class BatchPlusPlugin: DTHubPlugin {
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.batchplus", name: "Batch plus", version: "1.1", symbol: "square.stack.3d.up", families: nil)
  private let state = BatchPlusState()
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: BatchPlusView(state: state, send: { [weak self] in self?.send() }))
  }

  func start(host: DTHubHost) {
    self.host = host
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      state.apply(context: message)
      return nil
    case "project":
      // The state of the tab belongs to the open project.
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
    guard !state.isSending, let host, let pipeline = state.pipeline() else { return }
    state.isSending = true
    state.status = L.text(.sending)
    Task {
      let answer = await host.contribute(["pipeline": pipeline])
      state.status = BatchPlusState.describe(answer, italian: L.systemIsItalian)
      state.isSending = false
      // The next send of the same text comes out in another random order.
      state.reshuffle()
    }
  }
}

@objc(BatchPlusEntry)
public final class BatchPlusEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { BatchPlusPlugin() }
}
