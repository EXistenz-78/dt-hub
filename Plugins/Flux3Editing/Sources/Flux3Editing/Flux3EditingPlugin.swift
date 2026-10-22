import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class Flux3EditingPlugin: DTHubPlugin {
  /// Le famiglie del plug-in, in un solo punto. Per ora FLUX.2 [klein] (come Prompt Master F3), così si prova nell'app fino
  /// alla generazione del prompt; quando Draw Things espone FLUX.3 Klein si aggiunge il suo id (sconosciuto: nessuna ipotesi).
  static let families = ["flux2_9b", "flux2_4b"]

  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.flux3editing", name: "Flux3 Editing", version: "1.0", symbol: "rectangle.on.rectangle",
    families: Flux3EditingPlugin.families)
  private let state = EditState()
  private var host: DTHubHost?

  init() {
    // Il master prompt, scritto in Data/prompt-master-flux3-editing se manca o è più vecchio (e `custom/`).
    EditPrompts.install()
  }

  func makeViewController() -> NSViewController {
    NSHostingController(
      rootView: EditView(state: state, send: { [weak self] in self?.send() }, write: { [weak self] in self?.write() }))
  }

  func start(host: DTHubHost) { self.host = host }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) { state.update(context: context) }
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
    guard state.canWrite, let host else { return }
    state.isWriting = true
    state.status = L.text(.writing, italian: state.italian)
    let document = state.document
    let (allowed, system, refs) = (state.allowedTags, state.writeSystem, state.refs)
    let attachments = state.llmAttachments()
    let writer = EditWriter(
      ask: { prompt, system, options, images in
        await host.askLanguageModelAnswer(prompt, images: images, system: system, options: options)
      },
      italian: state.italian)
    Task {
      let result = await writer.write(document: document, refs: refs, allowedTags: allowed, attachments: attachments, system: system, options: EditPrompts.options)
      let before = EditSnapshot.take(from: document)
      state.apply(result)
      if let folder = state.projectFolder, !result.request.isEmpty {
        EditWorkFolder(folder: folder).write(request: result.request, answer: result.answer, before: before)
      }
      state.isWriting = false
    }
  }

  private func send() {
    guard state.canSend, let host else { return }
    state.isSending = true
    state.status = ""
    let sender = EditSender(contribute: { await host.contribute($0) }, italian: state.italian)
    let text = state.sendText
    Task {
      let outcome = await sender.send(text)
      state.status = outcome.status
      state.isSending = false
    }
  }
}

@objc(Flux3EditingEntry)
public final class Flux3EditingEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { Flux3EditingPlugin() }
}
