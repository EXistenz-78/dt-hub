import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class MossPlugin: DTHubPlugin {
  /// Le famiglie del plug-in, in un solo punto: MOSS Image (Base e SFT) ha la `version` `mossImage` nell'elenco ufficiale
  /// dei modelli di Draw Things e `moss_image` nelle sue configurazioni; l'app non normalizza.
  static let families = ["moss_image", "mossImage"]

  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.promptmastermoss", name: "Prompt Master MOSS", version: "1.1", symbol: "wand.and.stars",
    families: MossPlugin.families, tools: MossTools.declarations)
  let state: MossState
  private var host: DTHubHost?

  /// `dataFolder` e `store` si iniettano nei test; l'app usa la cartella Data e le preferenze vere.
  init(dataFolder: URL = DataSource.defaultFolder, store: MossStore = MossStore()) {
    // Il master prompt, scritto in Data/prompt-master-moss se manca o è più vecchio (e `custom/`).
    MossPrompts.install(dataFolder: dataFolder)
    state = MossState(
      data: MossData.load(folder: dataFolder), promptFolder: MossPrompts.folder(dataFolder: dataFolder), store: store)
  }

  func makeViewController() -> NSViewController {
    NSHostingController(
      rootView: MossView(state: state, send: { [weak self] in self?.send() }, write: { [weak self] in self?.write() }))
  }

  func start(host: DTHubHost) { self.host = host }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      state.update(generationSize: GenerationSize.read(fromContext: message))
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) {
        state.update(models: context.languageModels ?? [], family: context.family)
      }
      return nil
    case "tool.call":
      guard let call = DTHubToolCall(message) else { return DTHubMessage.failure("Not a tool call.") }
      let actions = MossTools.Actions(
        write: { [weak self] in await self?.performWrite() }, send: { [weak self] in await self?.performSend() })
      return await MossTools.handle(call, state: state, actions: actions)
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

  /// Quello che «Invia» manda: il JSON e il negativo; nil se non si può inviare.
  func sendPayload() -> (json: String, negative: String)? {
    guard state.canSend, let json = state.currentJSON() else { return nil }
    return (json, state.negativeText)
  }

  private func write() { Task { _ = await performWrite() } }

  /// The button and the `write_with_llm` tool: nil when the tab cannot write now.
  private func performWrite() async -> MossTools.WriteReport? {
    guard state.canWrite, let host else { return nil }
    state.isWriting = true
    state.status = L.text(.writing, italian: state.italian)
    let document = state.document
    let (catalog, system, options, model) = (state.catalog, state.writeSystem, state.writeOptions, state.writeModel)
    let writer = MossWriter(
      ask: { prompt, system, options in await host.askLanguageModelAnswer(prompt, system: system, model: model, options: options) },
      italian: state.italian)
    let result = await writer.write(document: document, catalog: catalog, system: system, options: options)
    let before = MossSnapshot.take(from: document)
    state.apply(result)
    if let folder = state.projectFolder, !result.request.isEmpty {
      MossWorkFolder(folder: folder).write(request: result.request, answer: result.answer, before: before)
    }
    state.isWriting = false
    return MossTools.WriteReport(wrote: !result.rewrites.isEmpty, status: state.status)
  }

  private func send() { Task { _ = await performSend() } }

  /// The «Send» button and the `send_to_generation` tool.
  private func performSend() async -> PromptSender.Outcome? {
    guard let host, let payload = sendPayload() else { return nil }
    state.isSending = true
    state.status = ""
    let sender = PromptSender(contribute: { await host.contribute($0) }, italian: state.italian)
    let outcome = await sender.send(payload.json, negative: payload.negative)
    state.status = outcome.status
    state.isSending = false
    return outcome
  }
}

@objc(PromptMasterMOSSEntry)
public final class PromptMasterMOSSEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { MossPlugin() }
}
