import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class MingPlugin: DTHubPlugin {
  /// Le famiglie del plug-in, in un solo punto: Ming-Image 0.1 Design è `ming_image` nel `custom.json` del server di DT Hub.
  static let families = ["ming_image", "mingImage"]

  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.promptmasterming", name: "Prompt Master Ming", version: "1.0", symbol: "wand.and.stars",
    families: MingPlugin.families, tools: MingTools.declarations)
  let state: MingState
  private var host: DTHubHost?

  /// `dataFolder` e `store` si iniettano nei test; l'app usa la cartella Data e le preferenze vere.
  init(dataFolder: URL = DataSource.defaultFolder, store: MingStore = MingStore()) {
    MingPrompts.install(dataFolder: dataFolder)
    state = MingState(
      data: MingData.load(folder: dataFolder), promptFolder: MingPrompts.folder(dataFolder: dataFolder), store: store)
  }

  func makeViewController() -> NSViewController {
    NSHostingController(
      rootView: MingView(
        state: state, send: { [weak self] in self?.send() }, write: { [weak self] in self?.write() },
        compose: { [weak self] in self?.compose() }, importPrompt: { [weak self] in self?.importFromGeneration() }))
  }

  func start(host: DTHubHost) { self.host = host }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      state.update(generationSize: GenerationSize.read(fromContext: message))
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) {
        let isMing = context.family.map(MingPlugin.families.contains) ?? false
        state.update(
          models: context.languageModels ?? [], family: context.family,
          familyPrompt: isMing ? context.promptGuide?.familyPrompt : nil)
        if let prompt = context.prompt { state.update(generationPrompt: prompt) }
      }
      return nil
    case "tool.call":
      guard let call = DTHubToolCall(message) else { return DTHubMessage.failure("Not a tool call.") }
      let actions = MingTools.Actions(
        write: { [weak self] in await self?.performWrite() }, compose: { [weak self] in await self?.performCompose() },
        send: { [weak self] in await self?.performSend() },
        resize: { [weak self] size in await self?.requestSize(size) ?? false })
      return await MingTools.handle(call, state: state, actions: actions)
    case "project":
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

  // MARK: Importa

  private func importFromGeneration() {
    Task {
      if case .success(let size?) = state.importFromGeneration() { _ = await requestSize(size) }
    }
  }

  /// Chiede all'app la dimensione della Generazione per la forma di un JSON importato; true se l'ha presa.
  func requestSize(_ size: PixelSize) async -> Bool {
    guard let host else { return false }
    state.beginImportSize()
    defer { state.endImportSize() }
    let answer = await host.contribute(["fields": ["width": size.width, "height": size.height]])
    let accepted = PromptSender.wasAccepted(answer)
    if accepted {
      state.update(generationSize: size)
      state.status += " " + L.format(.sizeChangedForImport, size.width, size.height, italian: state.italian)
    } else {
      state.status += " " + L.format(.sizeNotChanged, size.width, size.height, italian: state.italian)
    }
    return accepted
  }

  // MARK: Invia

  func sendPayload() -> String? {
    guard state.canSend else { return nil }
    return state.currentJSON()
  }

  private func send() { Task { _ = await performSend() } }

  private func performSend() async -> PromptSender.Outcome? {
    guard let host, let json = sendPayload() else { return nil }
    state.isSending = true
    state.status = ""
    let sender = PromptSender(contribute: { await host.contribute($0) }, italian: state.italian)
    let outcome = await sender.send(json)
    // Il prompt della Generazione ora è il JSON del tab: non si offre di importarlo.
    if outcome.sent { state.update(generationPrompt: json) }
    state.status = outcome.status
    state.isSending = false
    return outcome
  }

  // MARK: Scrivi e componi con LLM

  private func writer(_ host: DTHubHost) -> MingWriter {
    let model = state.writeModel
    return MingWriter(
      ask: { prompt, system, options in await host.askLanguageModelAnswer(prompt, system: system, model: model, options: options) },
      italian: state.italian)
  }

  private func write() { Task { _ = await performWrite() } }

  private func performWrite() async -> MingTools.WriteReport? {
    guard state.canWrite, let host else { return nil }
    state.isWriting = true
    state.status = L.text(.writing, italian: state.italian)
    let document = state.document
    let result = await writer(host).write(
      document: document, catalog: state.catalog, system: state.writeSystem, options: state.writeOptions)
    let before = MingSnapshot.take(from: document)
    state.apply(result)
    if let folder = state.projectFolder, !result.request.isEmpty {
      MingWorkFolder(folder: folder).write(request: result.request, answer: result.answer, before: before)
    }
    state.isWriting = false
    return MingTools.WriteReport(wrote: !result.rewrites.isEmpty, status: state.status)
  }

  private func compose() { Task { _ = await performCompose() } }

  private func performCompose() async -> MingTools.WriteReport? {
    guard state.canCompose, let host, let request = state.composeRequest() else { return nil }
    state.isWriting = true
    state.status = L.text(.writing, italian: state.italian)
    let before = MingSnapshot.take(from: state.document)
    let result = await writer(host).compose(request: request, system: state.composeSystem, options: state.writeOptions)
    var size: PixelSize?
    if let imported = result.imported {
      size = state.apply(imported: imported, source: "LLM")
      state.status = result.status + (imported.warnings.isEmpty ? "" : " " + imported.warnings.joined(separator: " "))
    } else {
      state.status = result.status
    }
    if let folder = state.projectFolder {
      MingWorkFolder(folder: folder).write(request: result.request, answer: result.answer, before: before)
    }
    state.isWriting = false
    // L'LLM ha scritto per la forma della Generazione: una forma diversa nel suo JSON non la cambia.
    _ = size
    return MingTools.WriteReport(wrote: result.imported != nil, status: state.status)
  }
}

@objc(PromptMasterMingEntry)
public final class PromptMasterMingEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { MingPlugin() }
}
