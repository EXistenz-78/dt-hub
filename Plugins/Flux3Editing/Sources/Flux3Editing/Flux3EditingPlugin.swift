import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class Flux3EditingPlugin: DTHubPlugin {
  /// Le famiglie del plug-in, in un solo punto: FLUX.3 [klein] 5.6B, con le sue varianti Base e quantizzate, ha la `version`
  /// `flux3_5b` nell'elenco dei modelli di Draw Things.
  static let families = ["flux3_5b"]

  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.flux3editing", name: "Flux3 Editing", version: "1.1", symbol: "scribble.variable",
    families: Flux3EditingPlugin.families)
  private let state = EditState()
  private var host: DTHubHost?

  init() {
    // Il master prompt, scritto in Data/flux3-editing se manca o è più vecchio (e `custom/`).
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
    let pictures = state.llmPictures()
    let leftOut = state.droppedPictures
    let writer = EditWriter(
      ask: { prompt, system, options, images in
        await host.askLanguageModelAnswer(prompt, images: images, system: system, options: options)
      },
      italian: state.italian)
    Task {
      let result = await writer.write(document: document, refs: refs, allowedTags: allowed, pictures: pictures, system: system, options: EditPrompts.options)
      let before = EditSnapshot.take(from: document)
      state.apply(result)
      if state.document.sendsImages, !leftOut.isEmpty {
        state.status += " " + L.format(.picturesLeftOut, leftOut.map { "<ref_image_\($0)>" }.joined(separator: ", "), italian: state.italian)
      }
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
