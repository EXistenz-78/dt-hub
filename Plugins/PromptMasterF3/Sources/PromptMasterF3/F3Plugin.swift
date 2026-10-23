import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class F3Plugin: DTHubPlugin {
  /// Le famiglie del plug-in, in un solo punto: FLUX.3 [klein] 5.6B, con le sue varianti Base e quantizzate, ha la `version`
  /// `flux3_5b` nell'elenco dei modelli di Draw Things.
  static let families = ["flux3_5b"]

  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.promptmasterf3", name: "Prompt Master F3", version: "1.0.1", symbol: "wand.and.stars",
    families: F3Plugin.families)
  private let state = F3State()
  private var host: DTHubHost?

  init() {
    // Il master prompt, scritto in Data/prompt-master-f3 se manca o è più vecchio (e `custom/`).
    F3Prompts.install()
  }

  func makeViewController() -> NSViewController {
    NSHostingController(
      rootView: F3View(state: state, send: { [weak self] in self?.send() }, write: { [weak self] in self?.write() }))
  }

  func start(host: DTHubHost) { self.host = host }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      state.update(generationSize: GenerationSize.read(fromContext: message))
      return nil
    case "project":
      // La sessione del tab appartiene al progetto aperto.
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
    state.commitComposition()
    guard state.canWrite, let host else { return }
    state.isWriting = true
    state.status = L.text(.writing, italian: state.italian)
    let document = state.document
    let (catalog, system, options) = (state.catalog, state.writeSystem, state.writeOptions)
    let writer = F3Writer(
      ask: { prompt, system, options in await host.askLanguageModelAnswer(prompt, system: system, options: options) },
      italian: state.italian)
    Task {
      let result = await writer.write(document: document, catalog: catalog, system: system, options: options)
      let before = F3Snapshot.take(from: document)
      state.apply(result)
      if let folder = state.projectFolder, !result.request.isEmpty {
        F3WorkFolder(folder: folder).write(request: result.request, answer: result.answer, before: before)
      }
      state.isWriting = false
    }
  }

  private func send() {
    state.commitComposition()
    guard state.canSend, let host else { return }
    state.isSending = true
    state.status = ""
    let sender = F3Sender(contribute: { await host.contribute($0) }, italian: state.italian)
    let text = state.sendText
    Task {
      let outcome = await sender.send(text)
      state.status = outcome.status
      state.isSending = false
    }
  }
}

@objc(PromptMasterF3Entry)
public final class PromptMasterF3Entry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { F3Plugin() }
}
