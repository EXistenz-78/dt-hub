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
  private let state = PFState()
  private var host: DTHubHost?
  private var presetsAccepted = false
  /// The folder of the open project, for the tests.
  var projectFolderForTests: URL? { state.projectFolder }

  /// `dataFolder` is where the master prompt is written (a test gives another one).
  init(dataFolder: URL = PFPrompt.defaultDataFolder) {
    PFPrompt.install(dataFolder: dataFolder)
  }

  func makeViewController() -> NSViewController {
    NSHostingController(
      rootView: PFView(
        state: state,
        actions: PFViewActions(
          improve: { [weak self] in self?.improve() }, send: { [weak self] in self?.send() },
          fixSeam: { [weak self] in self?.fixSeam() },
          cutoutStart: { [weak self] in self?.cutout { await $0.sendCutoutAsStartImage(contribute: $1) } },
          cutoutMoodboard: { [weak self] in self?.cutout { await $0.addCutoutToMoodboard(contribute: $1) } },
          putBackPanorama: { [weak self] in self?.cutout { await $0.putBackInPanorama(contribute: $1) } })))
  }

  func start(host: DTHubHost) {
    self.host = host
    registerPresetsInBackground()
  }

  /// Offers the two presets until the app takes them: it refuses while the plug-in is off for the model, so it is tried again when the plug-in turns on
  /// and before each send. A name already in the menu is left alone, so repeating is harmless.
  func registerPresets(using send: PFPresetSender) async {
    guard !presetsAccepted else { return }
    if await PFPresets.register(using: send)?["type"] as? String == "ok" { presetsAccepted = true }
  }

  private func registerPresetsInBackground() {
    guard let host else { return }
    Task { await registerPresets(using: { await host.registerPresets($0) }) }
  }

  private func send() {
    guard let host else { return }
    Task {
      await registerPresets(using: { await host.registerPresets($0) })
      await state.send(contribute: { await host.contribute($0) })
    }
  }

  /// Runs a Cutout action with the app's `contribute`.
  private func cutout(_ action: @escaping (PFState, PFContribute) async -> Void) {
    guard let host else { return }
    Task { await action(state, { await host.contribute($0) }) }
  }

  private func fixSeam() {
    guard let host else { return }
    Task {
      await registerPresets(using: { await host.registerPresets($0) })
      await state.fixSeam(contribute: { await host.contribute($0) })
    }
  }

  private func improve() {
    guard let host else { return }
    Task {
      await state.improve { prompt, system, images in
        await host.askLanguageModelAnswer(prompt, images: images, system: system, options: PFPrompt.options)
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
    case "session.next":
      return await state.sessionNext(message)
    case "session.end":
      if let host { await state.sessionEnded(message, contribute: { await host.contribute($0) }) }
      return nil
    case "activate":
      registerPresetsInBackground()
      return nil
    case "deactivate": return nil
    default: return DTHubMessage.bare("unsupported")
    }
  }
}

@objc(Panorama360F3Entry)
public final class Panorama360F3Entry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { Panorama360F3Plugin() }
}
