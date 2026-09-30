import CoreGraphics
import Foundation
import HubCore
import HubKit
import Observation

/// App-level state of the Generation tab: prompt, parameters, card states, and the session
/// that runs them (spec §6, §7). Lives as long as the app.
@MainActor
@Observable
final class GenerationController {
  var prompt = ""
  var parameters = GenerationParameters.default
  /// When on, width and height move together to keep `lockedRatio`.
  var lockRatio = false {
    didSet { lockedRatio = lockRatio ? currentRatio : nil }
  }
  /// Width ÷ height kept while `lockRatio` is on.
  private(set) var lockedRatio: Double?
  let session = GenerationSession(store: CurrentFolderImageStore())
  let cards = CardExpansionStore(fileURL: CardExpansionStore.defaultFileURL)
  private(set) var outputFolder: URL

  @ObservationIgnored private let outputSettings = OutputSettingsStore()

  init() {
    outputFolder = outputSettings.folder()
  }

  /// Starts a RUN when the server, the model and the session allow it.
  func run(with connection: DrawThingsConnection) {
    let monitor = connection.monitor
    guard !session.isRunning,
      let backend = monitor.backend,
      let model = connection.selection.selectedFile,
      RunAvailability.blocker(connection: monitor.status, selectedModel: model, catalog: monitor.catalog) == nil
    else { return }
    let job = GenerationJob(prompt: prompt, model: model, parameters: parameters.resolvedForRun())
    session.start(job, backend: backend, monitor: monitor)
  }

  /// "Resume parameters": puts a result's prompt, parameters (with its seed) and model back.
  func resume(_ result: GeneratedImage, with connection: DrawThingsConnection) {
    prompt = result.job.prompt
    parameters = result.job.parameters
    connection.selection.select(result.job.model)
  }

  func apply(_ ratio: AspectRatio) {
    parameters.apply(ratio)
    if lockRatio { lockedRatio = currentRatio }
  }

  func swapDimensions() {
    parameters.swapDimensions()
    if lockRatio { lockedRatio = currentRatio }
  }

  private var currentRatio: Double {
    Double(parameters.width) / Double(max(parameters.height, 1))
  }

  func setOutputFolder(_ url: URL) {
    outputSettings.setFolder(url)
    outputFolder = url
  }
}

/// Saves into the Output folder chosen at the moment of saving.
struct CurrentFolderImageStore: ImageStore {
  func save(_ image: CGImage, job: GenerationJob, index: Int, date: Date) throws -> URL {
    try PNGImageStore(folder: OutputSettingsStore().folder()).save(image, job: job, index: index, date: date)
  }
}
