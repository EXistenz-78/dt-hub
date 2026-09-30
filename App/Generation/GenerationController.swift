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

  /// True when the server, the model and the session allow a RUN.
  func canRun(with connection: DrawThingsConnection) -> Bool {
    let monitor = connection.monitor
    return !session.isRunning && monitor.backend != nil
      && RunAvailability.blocker(
        connection: monitor.status, selectedModel: connection.selection.selectedFile, catalog: monitor.catalog) == nil
  }

  /// Starts a RUN, split into its batches (`batchesForRun`). With a random seed, the seed
  /// drawn for the first batch is shown in the Seed field.
  @discardableResult
  func run(with connection: DrawThingsConnection) -> Bool {
    guard canRun(with: connection), let backend = connection.monitor.backend,
      let model = connection.selection.selectedFile
    else { return false }
    let batches = parameters.batchesForRun().map { GenerationJob(prompt: prompt, model: model, parameters: $0) }
    if parameters.randomSeed, let first = batches.first { parameters.seed = first.parameters.seed }
    session.start(batches, backend: backend, monitor: connection.monitor)
    return true
  }

  /// "Resume parameters": puts back the prompt, model and parameters of the batch that made
  /// the image (its seed, batch count 1). A ratio lock follows the resumed size.
  func resume(_ result: GeneratedImage, with connection: DrawThingsConnection) {
    prompt = result.job.prompt
    parameters = result.job.parameters
    if lockRatio { lockedRatio = currentRatio }
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
