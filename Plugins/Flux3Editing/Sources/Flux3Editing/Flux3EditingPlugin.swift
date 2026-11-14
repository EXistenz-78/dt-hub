import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class Flux3EditingPlugin: DTHubPlugin {
  /// Le famiglie del plug-in, in un solo punto: FLUX.3 [klein] 5.6B, con le sue varianti Base e quantizzate, ha la `version`
  /// `flux3_5b` nell'elenco dei modelli di Draw Things.
  static let families = ["flux3_5b"]

  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.flux3editing", name: "Flux3 Editing", version: "1.3", symbol: "scribble.variable",
    families: Flux3EditingPlugin.families, tools: FETools.declarations)
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
    case "tool.call":
      guard let call = DTHubToolCall(message), let host else { return DTHubMessage.bare("unsupported") }
      let connection = FETools.Connection(
        improve: { [state] in await state.improve(ask: Self.ask(host)) },
        sender: EditSender(contribute: { await host.contribute($0) }, italian: false))
      return await FETools.handle(call, state: state, connection: connection)
    default:
      return DTHubMessage.bare("unsupported")
    }
  }

  private func write() {
    guard state.canWrite, let host else { return }
    state.isWriting = true
    Task { await state.improve(ask: Self.ask(host)) }
  }

  /// «Migliora prompt»: la domanda al modello linguistico che sceglie l'app.
  private static func ask(_ host: DTHubHost) -> @MainActor (String, String, DTHubLLMOptions, [String], String?) async -> DTHubLLMAnswer {
    { prompt, system, options, images, model in
      await host.askLanguageModelAnswer(prompt, images: images, system: system, model: model, options: options)
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
