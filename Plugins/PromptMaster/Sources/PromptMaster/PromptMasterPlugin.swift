import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class PromptMasterPlugin: DTHubPlugin {
  /// Its tab is grey on the other families: those are the ones Prompt Master has a master prompt for.
  let manifest = DTHubManifest(
    id: "com.exiztenz.dthub.promptmaster", name: "Prompt Master", version: "1.0", symbol: "wand.and.stars",
    families: PMFamilies.all)
  private let state = PMState()
  private var host: DTHubHost?

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
          family: context.family, languageModels: context.languageModels ?? [], width: size?.width, height: size?.height)
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

  private func makeWriter(_ host: DTHubHost) -> PMWriter {
    PMWriter(
      ask: { prompt, system, model, options in
        await host.askLanguageModelAnswer(prompt, system: system, model: model, options: options)
      },
      contribute: { await host.contribute($0) }, italian: state.italian)
  }

  private func write() {
    guard state.canWrite, let host, let request = state.writeRequest else { return }
    state.isWriting = true
    state.status = ""
    state.suggestedRatio = nil
    let writer = makeWriter(host)
    Task {
      let outcome = await writer.write(request)
      state.status = outcome.status
      state.suggestedRatio = outcome.ratio
      state.isWriting = false
    }
  }

  private func applyRatio() {
    guard state.canApplyRatio, let host, let ratio = state.suggestedRatio else { return }
    let (width, height) = (state.currentWidth, state.currentHeight)
    let writer = makeWriter(host)
    Task {
      let outcome = await writer.applyRatio(ratio, currentWidth: width, currentHeight: height)
      state.status = outcome.status
      if outcome.sent { state.suggestedRatio = nil }
    }
  }

  private func makeScene() {
    guard !state.isMakingScene, !state.isWriting, let host else { return }
    state.isMakingScene = true
    let writer = makeWriter(host)
    Task {
      switch await writer.scene() {
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
