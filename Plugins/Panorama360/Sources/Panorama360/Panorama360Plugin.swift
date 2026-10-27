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
  private var presetsAccepted = false
  /// The folder of the open project, for the tests.
  var projectFolderForTests: URL? { state.projectFolder }

  /// `dataFolder` is where the master prompt is written (a test gives another one).
  init(dataFolder: URL = PSPrompt.defaultDataFolder) {
    PSPrompt.install(dataFolder: dataFolder)
  }

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: PSView(state: state, actions: PSViewActions(
          improve: { [weak self] in self?.improve() }, send: { [weak self] in self?.send() },
          cutoutStart: { [weak self] in self?.cutout { await $0.sendCutoutAsStartImage(contribute: $1) } },
          cutoutMoodboard: { [weak self] in self?.cutout { await $0.addCutoutToMoodboard(contribute: $1) } },
          putBackPanorama: { [weak self] in self?.cutout { await $0.putBackInPanorama(contribute: $1) } },
          fixSeam: { [weak self] in self?.cutout { await $0.prepareSeamCorrection(contribute: $1) } })))
  }

  func start(host: DTHubHost) {
    self.host = host
    registerPresetsInBackground()
  }

  /// Offers the two presets until the app takes them: it refuses while the plug-in is off for the model (a non-FLUX.2 model at launch), so
  /// it is tried again when the plug-in turns on and before each send. A name already in the menu is left alone, so repeating is harmless.
  func registerPresets(using send: PSPresetSender) async {
    guard !presetsAccepted else { return }
    if await PSPresets.register(using: send)?["type"] as? String == "ok" { presetsAccepted = true }
  }

  private func registerPresetsInBackground() {
    guard let host else { return }
    Task { await registerPresets(using: { await host.registerPresets($0) }) }
  }

  /// Runs a Cutout action with the app's `contribute`.
  private func cutout(_ action: @escaping (PSState, PSContribute) async -> Void) {
    guard let host else { return }
    Task { await action(state, { await host.contribute($0) }) }
  }

  private func send() {
    guard let host else { return }
    Task {
      await registerPresets(using: { await host.registerPresets($0) })
      await state.send(contribute: { await host.contribute($0) })
    }
  }

  private func improve() {
    guard let host else { return }
    Task {
      await state.improve { prompt, system, images in
        await host.askLanguageModelAnswer(prompt, images: images, system: system, options: PSPrompt.options)
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
    case "queue.capture":
      guard let request = DTHubQueueCapture(message), let captured = state.queueCapture(folder: request.folder) else {
        return DTHubMessage.failure(state.text(.queueNotPrepared))
      }
      return DTHubMessage.ok(state: captured)
    case "queue.prepare":
      guard let host, let request = DTHubQueuePrepare(message) else { return DTHubMessage.failure(state.text(.seamUnreadable)) }
      let problem = await state.queuePrepare(
        folder: request.folder, state: request.state, model: request.model, contribute: { await host.contribute($0) })
      return problem.map(DTHubMessage.failure) ?? DTHubMessage.ok()
    case "session.next":
      return await state.seamNext(message)
    case "session.end":
      if let host { await state.seamEnded(message, contribute: { await host.contribute($0) }) }
      return nil
    case "activate":
      registerPresetsInBackground()
      return nil
    case "deactivate": return nil
    default: return DTHubMessage.bare("unsupported")
    }
  }
}

@objc(Panorama360Entry)
public final class Panorama360Entry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { Panorama360Plugin() }
}
