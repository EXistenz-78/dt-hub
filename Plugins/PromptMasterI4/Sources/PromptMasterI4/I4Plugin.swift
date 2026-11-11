import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class PromptMasterI4Plugin: DTHubPlugin {
  /// On the other families the plug-in is switched off and its tab is hidden: this plug-in writes the caption of Ideogram 4 only.
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.promptmasteri4", name: "Prompt Master I4", version: "1.4", symbol: "wand.and.stars",
    families: ["ideogram_4"], tools: I4Tools.declarations)
  private let state = I4State()

  init() {
    // The master prompt, written to Data/prompt-master-i4 if missing or older (and custom/ made).
    I4Prompts.install()
  }
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
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) {
        state.update(models: context.languageModels ?? [], family: context.family)
      }
      return nil
    case "tool.call":
      guard let call = DTHubToolCall(message) else { return DTHubMessage.failure("Not a tool call.") }
      let actions = I4Tools.Actions(
        write: { [weak self] in await self?.performWrite() }, send: { [weak self] in await self?.performSend() })
      return await I4Tools.handle(call, state: state, actions: actions)
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

  private func write() { Task { _ = await performWrite() } }

  /// The button and the `write_with_llm` tool: nil when the tab cannot write now.
  private func performWrite() async -> I4Writer.Outcome? {
    guard state.canWrite, let host else { return nil }
    let all = state.fields
    let targets = all.filter(\.needsWriting)
    state.beginWriting()
    state.status = L.text(.writing, italian: state.italian)
    let model = state.writeModel
    let writer = I4Writer(
      ask: { prompt, system, options in await host.askLanguageModelAnswer(prompt, system: system, model: model, options: options) },
      italian: state.italian, progress: { [state] in state.status = $0 })
    let (system, options) = (state.writeSystem, state.writeOptions)
    let outcome = await writer.write(targets: targets, fields: all, system: system, options: options)
    state.apply(outcome)
    state.isWriting = false
    return outcome
  }

  private func send() { Task { _ = await performSend() } }

  /// The «Send» button and the `send_to_generation` tool.
  private func performSend() async -> PromptSender.Outcome? {
    guard state.canSend, let host else { return nil }
    state.isSending = true
    state.status = ""
    let sender = PromptSender(contribute: { await host.contribute($0) }, italian: state.italian)
    let outcome = await sender.send(state.jsonText)
    state.status = outcome.status
    state.isSending = false
    return outcome
  }
}

@objc(PromptMasterI4Entry)
public final class PromptMasterI4Entry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { PromptMasterI4Plugin() }
}
