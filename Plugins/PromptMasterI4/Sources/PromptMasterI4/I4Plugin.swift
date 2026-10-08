import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class PromptMasterI4Plugin: DTHubPlugin {
  /// On the other families the plug-in is switched off and its tab is hidden: this plug-in writes the caption of Ideogram 4 only.
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.promptmasteri4", name: "Prompt Master I4", version: "1.1", symbol: "curlybraces",
    families: ["ideogram_4"])
  private let state = I4State()
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(
      rootView: I4View(state: state, send: { [weak self] in self?.send() }, write: { [weak self] in self?.write() }))
  }

  func start(host: DTHubHost) {
    self.host = host
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      state.update(generationSize: GenerationSize.read(fromContext: message))
      return nil
    case "project":
      // The session of the tab belongs to the open project.
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

  private func write() {
    guard state.canWrite, let host else { return }
    let all = state.fields
    let targets = all.filter(\.needsWriting)
    state.beginWriting()
    state.status = L.text(.writing, italian: state.italian)
    let writer = I4Writer(
      ask: { prompt, system, options in await host.askLanguageModelAnswer(prompt, system: system, options: options) },
      italian: state.italian, progress: { [state] in state.status = $0 })
    let (system, options) = (state.writeSystem, state.writeOptions)
    Task {
      let outcome = await writer.write(targets: targets, fields: all, system: system, options: options)
      state.apply(outcome)
      state.isWriting = false
    }
  }

  private func send() {
    guard state.canSend, let host else { return }
    state.isSending = true
    state.status = ""
    let sender = I4Sender(contribute: { await host.contribute($0) }, italian: state.italian)
    let text = state.jsonText
    Task {
      let outcome = await sender.send(text)
      state.status = outcome.status
      state.isSending = false
    }
  }
}

@objc(PromptMasterI4Entry)
public final class PromptMasterI4Entry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { PromptMasterI4Plugin() }
}
