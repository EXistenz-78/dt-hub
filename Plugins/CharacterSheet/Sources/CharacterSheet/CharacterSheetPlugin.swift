import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class CharacterSheetPlugin: DTHubPlugin {
  /// Qwen Image 2.1 only. On the other families the plug-in is switched off and its tab is hidden.
  static let families = ["qwen_image_2.1"]
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.charactersheet", name: "Character Sheet", version: "1.3", symbol: "person.text.rectangle",
    families: CharacterSheetPlugin.families, tools: CSTools.declarations)
  private let state = CSState(store: CSSettingsStore(folder: CSTemplates.defaultFolder))

  init() {
    // The texts of earlier versions were `.txt`: same content, now Markdown.
    CSTemplates.migrateLegacy(in: CSTemplates.defaultFolder)
  }
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
    case "project":
      // The settings of the tab are preferences for every project: nothing to switch.
      return nil
    case "activate":
      state.active = true
      return nil
    case "deactivate":
      state.active = false
      return nil
    case "tool.call":
      guard let call = DTHubToolCall(message), let host else { return DTHubMessage.bare("unsupported") }
      return await CSTools.handle(call, state: state, runner: makeRunner(host: host, italian: false))
    default:
      return DTHubMessage.bare("unsupported")
    }
  }

  private func prepare() {
    guard let host, state.beginPrepare() else { return }
    let runner = makeRunner(host: host, italian: L.systemIsItalian)
    let job = state.job
    Task {
      let outcome = await runner.prepare(job, progress: { state.status = $0 })
      state.endPrepare(status: outcome.line)
    }
  }

  /// What «Prepare» works with: the app (through `host`) and the plug-in's own folder.
  private func makeRunner(host: DTHubHost, italian: Bool) -> CSRunner {
    let folder = CSTemplates.defaultFolder
    return CSRunner(
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
      now: Date.init, templatesFolder: folder.path, italian: italian)
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
