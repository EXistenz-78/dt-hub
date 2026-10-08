import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class CharacterSheetPlugin: DTHubPlugin {
  /// Qwen Image 2.1 only. On the other families the plug-in is switched off and its tab is hidden.
  static let families = ["qwen_image_2.1"]
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.charactersheet", name: "Character Sheet", version: "1.0", symbol: "person.text.rectangle",
    families: CharacterSheetPlugin.families)
  private let state = CSState(store: CSSettingsStore(folder: CSTemplates.defaultFolder))
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(
      rootView: CharacterSheetView(
        state: state, prepare: { [weak self] in self?.prepare() }, openFolder: { Self.openTemplatesFolder() }))
  }

  func start(host: DTHubHost) {
    self.host = host
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) { state.update(from: context) }
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

  private func prepare() {
    guard let host, state.beginPrepare() else { return }
    let folder = CSTemplates.defaultFolder
    let runner = CSRunner(
      contribute: { await host.contribute($0) },
      ask: { request in
        await host.askLanguageModelAnswer(
          request.prompt, images: request.images, system: request.system, model: request.model,
          options: request.options)
      },
      copyImage: CSRunner.copyIntoFolder,
      readTemplate: { .success(CSTemplates.resolved($0, from: folder)) },
      readPESystem: { model in
        CSBrief.peSystem(
          inFolder: URL(fileURLWithPath: model.path, isDirectory: true),
          read: { try? String(contentsOf: $0, encoding: .utf8) })
      },
      now: Date.init, templatesFolder: folder.path, italian: L.systemIsItalian)
    let job = state.job
    Task {
      let outcome = await runner.prepare(job, progress: { state.status = $0 })
      state.endPrepare(status: outcome.line)
    }
  }

  /// Opens the folder of the text files. The files that are not there yet are written first (the built-in texts), so
  /// there is something to edit; delete a file to go back to the built-in text.
  private static func openTemplatesFolder() {
    let folder = CSTemplates.defaultFolder
    CSTemplates.seedMissing(in: folder)
    NSWorkspace.shared.open(folder)
  }
}

@objc(CharacterSheetEntry)
public final class CharacterSheetEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { CharacterSheetPlugin() }
}
