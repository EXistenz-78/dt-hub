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
  private var presetsRegistered = false
  /// The folder of the open project, for the tests.
  var projectFolderForTests: URL? { state.projectFolder }

  /// `dataFolder` is where the master prompt is written (a test gives another one).
  init(dataFolder: URL = PSPrompt.defaultDataFolder) {
    PSPrompt.install(dataFolder: dataFolder)
  }

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: PSView(state: state, actions: PSViewActions(improve: { [weak self] in self?.improve() }, send: { [weak self] in self?.send() })))
  }

  func start(host: DTHubHost) {
    self.host = host
    Task { await registerPresetsOnce(using: { await host.registerPresets($0) }) }
  }

  /// The two presets go to the app once per launch (a name already in the menu is left alone, so the user's own copies stay).
  func registerPresetsOnce(using send: PSPresetSender) async {
    guard !presetsRegistered else { return }
    presetsRegistered = true
    _ = await PSPresets.register(using: send)
  }

  private func send() {
    guard let host else { return }
    Task { await state.send(contribute: { await host.contribute($0) }) }
  }

  private func improve() {
    guard let host else { return }
    Task {
      await state.improve { prompt, system in
        await host.askLanguageModelAnswer(prompt, system: system, options: PSPrompt.options)
      }
    }
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
    case "activate", "deactivate": return nil
    default: return DTHubMessage.bare("unsupported")
    }
  }
}

@objc(Panorama360Entry)
public final class Panorama360Entry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { Panorama360Plugin() }
}
