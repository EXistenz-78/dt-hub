import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class PromptMasterPlugin: DTHubPlugin {
  /// On the other families the plug-in is switched off and its tab is hidden: those are the ones Prompt Master has a master prompt for.
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.promptmaster", name: "Prompt Master", version: "1.6", symbol: "wand.and.stars",
    families: PMFamilies.all, tools: PMTools.declarations)
  private let state = PMState()
  private var host: DTHubHost?

  init() {
    // The Rules of the task, written to Data/prompt-master/rules if missing or older (and custom/ made).
    PMPrompts.install()
  }

  func makeViewController() -> NSViewController {
    NSHostingController(
      rootView: PromptMasterView(
        state: state, write: { [weak self] in self?.write() }, makeScene: { [weak self] in self?.makeScene() },
        applyRatio: { [weak self] in self?.applyRatio() }))
  }

  func start(host: DTHubHost) {
    self.host = host
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) {
        let size = RatioSize.currentSize(inContext: message)
        state.update(
          family: context.family, guide: context.promptGuide, languageModels: context.languageModels ?? [], width: size?.width, height: size?.height)
      }
      return nil
    case "project":
      // The state of the tab belongs to the open project.
      if let project = try? JSONDecoder().decode(DTHubProject.self, from: message) {
        state.switchProject(folder: URL(fileURLWithPath: project.folder, isDirectory: true), adoptLegacy: project.adoptLegacy)
      }
      return nil
    case "tool.call":
      guard let call = DTHubToolCall(message) else { return DTHubMessage.failure("Not a tool call.") }
      let actions = PMTools.Actions(
        write: { [weak self] in await self?.performWrite() }, applyRatio: { [weak self] in await self?.performApplyRatio() })
      return await PMTools.handle(call, state: state, actions: actions)
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

  private func makeWriter(_ host: DTHubHost) -> PMWriter {
    PMWriter(
      ask: { prompt, system, model, options in
        await host.askLanguageModelAnswer(prompt, system: system, model: model, options: options)
      },
      contribute: { await host.contribute($0) }, italian: state.italian)
  }

  private func write() {
    Task { _ = await performWrite() }
  }

  /// The button and the `write_prompt` tool: nil when the tab cannot write now.
  private func performWrite() async -> PMWriter.Outcome? {
    guard state.canWrite, let host, let request = state.writeRequest else { return nil }
    state.isWriting = true
    state.status = ""
    state.suggestedRatio = nil
    let outcome = await makeWriter(host).write(request)
    state.status = outcome.status
    state.suggestedRatio = outcome.ratio
    state.isWriting = false
    return outcome
  }

  private func applyRatio() {
    Task { _ = await performApplyRatio() }
  }

  private func performApplyRatio() async -> PMWriter.Outcome? {
    guard state.canApplyRatio, let host, let ratio = state.suggestedRatio else { return nil }
    let outcome = await makeWriter(host).applyRatio(ratio, currentWidth: state.currentWidth, currentHeight: state.currentHeight)
    state.status = outcome.status
    if outcome.sent { state.suggestedRatio = nil }
    return outcome
  }

  private func makeScene() {
    guard !state.isMakingScene, !state.isWriting, let host else { return }
    state.isMakingScene = true
    let (family, models) = (state.family, state.languageModels)
    let writer = makeWriter(host)
    Task {
      switch await writer.scene(family: family, models: models) {
      case .success(let scene):
        state.description = scene
        state.status = ""
      case .failure(let failure):
        state.status = failure.text
      }
      state.isMakingScene = false
    }
  }
}

@objc(PromptMasterEntry)
public final class PromptMasterEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { PromptMasterPlugin() }
}
