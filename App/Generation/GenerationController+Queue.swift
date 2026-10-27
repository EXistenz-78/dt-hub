import Foundation
import HubCore
import HubKit

/// Why a capture stopped, in the words the user gets.
private struct QueueCaptureStop: Error { let text: String }

/// The queue's side of the Generation tab (queue design §5): what an entry saves, how it is put back, and the RUN that
/// is waited for.
extension GenerationController {
  /// The tabs as they are now, as a queue entry; nil with the reason when they cannot be queued (no model, a guided
  /// pipeline whose plug-in is closed or does not support the queue, a picture that cannot be copied). The entry's
  /// pictures are copied into its folder. Async: a guided pipeline's plug-in is asked for its own snapshot.
  func captureQueueEntry(
    in connection: DrawThingsConnection, store: QueueStore
  ) async -> (entry: QueueEntry?, problem: String?) {
    guard let model = connection.selection.selectedFile else {
      return (nil, String(localized: "queue.error.noModel"))
    }
    let held = contributions?.pipeline
    let id = UUID()
    let folder = store.folder(for: id)
    // What the tabs hold now is taken before the plug-in is asked: the user may change them while it answers.
    let preset = Preset(
      name: "", model: model, prompt: prompt, negativePrompt: negativePrompt, parameters: parameters)
    let locked = lockRatio
    do {
      var queued: QueuedPipeline?
      let inputs = try control.captureForQueue(into: folder)
      if let held {
        if held.pipeline.guided != nil {
          guard let pluginID = held.pluginID else { throw QueueCaptureStop(text: String(localized: "queue.error.guidedClosed")) }
          let pluginFolder = folder.appendingPathComponent("plugin", isDirectory: true)
          try FileManager.default.createDirectory(at: pluginFolder, withIntermediateDirectories: true)
          let answer = await guidedChannel?.request(
            PluginQueue.captureRequest(folder: pluginFolder), pluginID, PluginRegistry.unbounded)
          switch PluginQueue.parseCapture(answer) {
          case .success(let state):
            queued = .guided(pluginID: pluginID, name: held.pipeline.name, passes: held.pipeline.passCount, state: state)
          case .failure(let problem):
            throw QueueCaptureStop(text: Self.queueProblemText(problem, key: "queue.error.guidedRefused"))
          }
        } else if let name = held.userPipelineName {
          queued = .user(name: name)
        } else if let pluginID = held.pluginID {
          let steps = try store.copyingImages(of: held.pipeline.steps, forEntry: id)
          queued = .plugin(pluginID: pluginID, name: held.pipeline.name, steps: steps)
        }
      }
      return (QueueEntry(id: id, preset: preset, lockRatio: locked, control: inputs, pipeline: queued), nil)
    } catch let stop as QueueCaptureStop {
      try? FileManager.default.removeItem(at: folder)
      return (nil, stop.text)
    } catch {
      try? FileManager.default.removeItem(at: folder)
      return (nil, String(format: String(localized: "queue.error.copy"), error.localizedDescription))
    }
  }

  /// The words for a plug-in that cannot take part in the queue. `key` is the catalog entry for an error the plug-in gave.
  private static func queueProblemText(_ problem: PluginQueueProblem, key: String) -> String {
    switch problem {
    case .notLoaded: String(localized: "queue.error.guidedClosed")
    case .unsupported: String(localized: "queue.error.guidedUnsupported")
    case .refused(let text):
      String(format: NSLocalizedString(key, comment: ""), text.isEmpty ? "—" : text)
    }
  }

  /// Puts an entry on the tabs: model, prompt, negative prompt, parameters, Control and the pipeline of RUN. Returns why
  /// it could not be, or nil.
  func restoreQueueEntry(_ entry: QueueEntry, store: QueueStore, in connection: DrawThingsConnection) async -> String? {
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
    case .guided(let pluginID, _, _, let state):
      // Nothing else is on RUN, so the plug-in's proposal meets no other (no choice between two plug-ins appears).
      contributions?.removePipeline()
      let request = PluginQueue.prepareRequest(
        folder: store.folder(for: entry.id).appendingPathComponent("plugin", isDirectory: true), state: state,
        model: model, family: family(in: connection))
      let answer = await guidedChannel?.request(request, pluginID, PluginRegistry.unbounded)
      if let problem = PluginQueue.parsePrepare(answer) {
        return Self.queueProblemText(problem, key: "queue.error.guidedPrepare")
      }
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
  func restore(_ entry: QueueEntry) async -> String? { await generation.restoreQueueEntry(entry, store: store, in: connection) }
  func runAndWait() async -> QueueRunOutcome { await generation.runQueueEntryAndWait(in: connection) }
  func stop() { generation.stop() }
}
