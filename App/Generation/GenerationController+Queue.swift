import Foundation
import HubCore
import HubKit

/// The queue's side of the Generation tab (queue design §5): what an entry saves, how it is put back, and the RUN that
/// is waited for.
extension GenerationController {
  /// The tabs as they are now, as a queue entry; nil with the reason when they cannot be queued (no model, a
  /// pipeline a plug-in guides, a picture that cannot be copied). The entry's pictures are copied into its folder.
  func captureQueueEntry(in connection: DrawThingsConnection, store: QueueStore) -> (entry: QueueEntry?, problem: String?) {
    guard let model = connection.selection.selectedFile else {
      return (nil, String(localized: "queue.error.noModel"))
    }
    let held = contributions?.pipeline
    if held?.pipeline.guided != nil { return (nil, String(localized: "queue.error.guided")) }
    let id = UUID()
    let folder = store.folder(for: id)
    do {
      var queued: QueuedPipeline?
      if let held {
        if let name = held.userPipelineName {
          queued = .user(name: name)
        } else if let pluginID = held.pluginID {
          let steps = try store.copyingImages(of: held.pipeline.steps, forEntry: id)
          queued = .plugin(pluginID: pluginID, name: held.pipeline.name, steps: steps)
        }
      }
      let inputs = try control.captureForQueue(into: folder)
      let entry = QueueEntry(
        id: id, preset: Preset(name: "", model: model, prompt: prompt, negativePrompt: negativePrompt, parameters: parameters),
        lockRatio: lockRatio, control: inputs, pipeline: queued)
      return (entry, nil)
    } catch {
      try? FileManager.default.removeItem(at: folder)
      return (nil, String(format: String(localized: "queue.error.copy"), error.localizedDescription))
    }
  }

  /// Puts an entry on the tabs: model, prompt, negative prompt, parameters, Control and the pipeline of RUN. Returns why
  /// it could not be, or nil.
  func restoreQueueEntry(_ entry: QueueEntry, store: QueueStore, in connection: DrawThingsConnection) -> String? {
    let model = entry.preset.model
    if !model.isEmpty {
      guard connection.monitor.catalog.model(forFile: model) != nil else {
        return String(format: String(localized: "queue.error.modelMissing"), model)
      }
    }
    do {
      try control.restoreFromQueue(entry.control, from: store.folder(for: entry.id))
    } catch {
      return String(format: String(localized: "queue.error.copy"), String(describing: error))
    }
    if !model.isEmpty { connection.selection.select(model) }
    parameters = entry.preset.parameters
    prompt = entry.preset.prompt
    negativePrompt = entry.preset.negativePrompt
    lockRatio = entry.lockRatio
    switch entry.pipeline {
    case .user(let name):
      if let problem = selectPipeline(named: name) { return problem }
    case .plugin(let pluginID, let name, let steps):
      contributions?.setPipeline(PluginPipeline(name: name, steps: steps), pluginID: pluginID)
    case nil:
      contributions?.removePipeline()
    }
    return nil
  }

  /// Presses RUN and waits for it to end, a pipeline included.
  func runQueueEntryAndWait(in connection: DrawThingsConnection) async -> QueueRunOutcome {
    session.dismissFailure()
    let before = session.results.first?.id
    guard run(with: connection) else { return .failed(String(localized: "queue.error.cannotRun")) }
    // A pipeline is all inside `preparation`; a plain RUN hands over to the session, which is awaited next.
    await preparation?.value
    await session.waitUntilFinished()
    if session.lastRunWasStopped { return .stopped }
    if case .failed(let error) = session.phase { return .failed(String(describing: error)) }
    if session.results.first?.id == before { return .failed(String(localized: "queue.error.noResult")) }
    return .finished
  }
}

/// The queue's view of the app.
@MainActor
final class AppQueueHost: QueueHost {
  private let generation: GenerationController
  private let connection: DrawThingsConnection
  private let store: QueueStore

  init(generation: GenerationController, connection: DrawThingsConnection, store: QueueStore) {
    self.generation = generation
    self.connection = connection
    self.store = store
  }

  func canRun() -> Bool { generation.canRun(with: connection) }
  func restore(_ entry: QueueEntry) -> String? { generation.restoreQueueEntry(entry, store: store, in: connection) }
  func runAndWait() async -> QueueRunOutcome { await generation.runQueueEntryAndWait(in: connection) }
  func stop() { generation.stop() }
}
