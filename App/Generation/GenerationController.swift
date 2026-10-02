import DTBridge
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
  var prompt = "" {
    didSet { scheduleSessionSave() }
  }
  /// Sent only when the model's family uses it (`JobComposer`).
  var negativePrompt = "" {
    didSet { scheduleSessionSave() }
  }
  var parameters = GenerationParameters.default {
    didSet { scheduleSessionSave() }
  }
  /// When on, width and height move together to keep `lockedRatio`.
  var lockRatio = false {
    didSet {
      lockedRatio = lockRatio ? currentRatio : nil
      scheduleSessionSave()
    }
  }
  /// Width ÷ height kept while `lockRatio` is on.
  private(set) var lockedRatio: Double?
  let session = GenerationSession(
    store: CurrentFolderImageStore(), history: ResultsHistoryStore(fileURL: ResultsHistoryStore.defaultFileURL))
  let cards = CardExpansionStore(fileURL: CardExpansionStore.defaultFileURL)
  private(set) var outputFolder: URL

  /// The language model, freed when RUN is pressed if the settings say so (spec §9).
  @ObservationIgnored let languageModel: LanguageModelManager
  /// The Control tab's images (tab Control spec): the start image goes with every RUN.
  @ObservationIgnored let control: ControlStore
  /// True between pressing RUN and the generation starting: the language model is being freed
  /// and a parked server brought back.
  private(set) var isPreparing = false

  @ObservationIgnored private let outputSettings = OutputSettingsStore()
  @ObservationIgnored private let sessionStore: SessionStore
  @ObservationIgnored private var pendingSave: Task<Void, Never>?
  @ObservationIgnored private var preparation: Task<Void, Never>?

  /// Restores the last prompt and parameters (spec §11).
  init(
    languageModel: LanguageModelManager, control: ControlStore,
    sessionStore: SessionStore = SessionStore(fileURL: SessionStore.defaultFileURL)
  ) {
    self.languageModel = languageModel
    self.control = control
    // The strip of the Results window comes back from the last launches.
    Task { [session] in await session.restoreHistory() }
    self.sessionStore = sessionStore
    outputFolder = outputSettings.folder()
    if let snapshot = sessionStore.load() {
      prompt = snapshot.prompt
      negativePrompt = snapshot.negativePrompt
      parameters = snapshot.parameters.clamped()
      lockRatio = snapshot.lockRatio
      // Observers do not run inside init: the locked ratio is set here.
      lockedRatio = lockRatio ? currentRatio : nil
    }
    pendingSave?.cancel()
    pendingSave = nil
  }

  /// The saved presets (spec §6).
  let presets = PresetStore(fileURL: PresetStore.defaultFileURL)
  /// Reads and writes the Draw Things configuration JSON (spec §6, level 3).
  @ObservationIgnored let codec: any ConfigurationCodec = DrawThingsConfigurationCodec()

  /// The model and parameters on the tab, as the JSON editor sees them.
  func configurationState(in connection: DrawThingsConnection) -> ConfigurationState {
    ConfigurationState(model: connection.selection.selectedFile ?? "", parameters: parameters)
  }

  func exportJSON(in connection: DrawThingsConnection) -> String {
    codec.exportJSON(configurationState(in: connection))
  }

  /// Applies a complete or partial Draw Things JSON to the tab: parameters, extra settings
  /// and, when the text names one, the model. Throws the reason when the text is not valid.
  func applyJSON(_ json: String, with connection: DrawThingsConnection) throws(ConfigurationError) {
    let result = try codec.apply(json: json, to: configurationState(in: connection))
    parameters = result.parameters.fillingTriggers(from: connection.monitor.catalog)
    if lockRatio { lockedRatio = currentRatio }
    if !result.model.isEmpty, result.model != connection.selection.selectedFile {
      connection.selection.select(result.model)
    }
  }

  /// Saves the tab as a preset (parameters, model, negative prompt; never the prompt).
  /// False when the name is empty.
  @discardableResult
  func savePreset(named name: String, with connection: DrawThingsConnection) -> Bool {
    presets.save(
      Preset(
        name: name, model: connection.selection.selectedFile ?? "", negativePrompt: negativePrompt,
        parameters: parameters))
  }

  /// Puts a preset on the tab; the prompt stays.
  func load(_ preset: Preset, with connection: DrawThingsConnection) {
    let load = PresetLoad.of(preset, currentNegativePrompt: negativePrompt, catalog: connection.monitor.catalog)
    parameters = load.parameters
    negativePrompt = load.negativePrompt
    if lockRatio { lockedRatio = currentRatio }
    if let model = load.model { connection.selection.select(model) }
  }

  /// Adds the presets of a file (a JSON list of `{name, configuration}`).
  func importPresets(from url: URL) -> PresetImportResult {
    guard let data = try? Data(contentsOf: url) else { return PresetImportResult(presets: [], skipped: 1) }
    let result = PresetImport.read(data, codec: codec)
    presets.add(imported: result.presets)
    return result
  }

  /// The chosen model as the server describes it; nil while the catalog is not loaded.
  func selectedModel(in connection: DrawThingsConnection) -> CatalogModel? {
    connection.selection.selectedModel(in: connection.monitor.catalog)
  }

  /// The family of the chosen model, nil when unknown or while the catalog is not loaded.
  func family(in connection: DrawThingsConnection) -> String? {
    selectedModel(in: connection)?.family
  }

  /// Which base fields the chosen model's family uses.
  func traits(in connection: DrawThingsConnection) -> FamilyTraits {
    FamilyTraits.of(family(in: connection))
  }

  /// Writes the session half a second after the last change, so typing does not write
  /// the file at every keystroke.
  private func scheduleSessionSave() {
    pendingSave?.cancel()
    pendingSave = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      self?.saveSessionNow()
    }
  }

  /// Writes the session at once (also when the app quits); a failure only loses the restore.
  func saveSessionNow() {
    pendingSave?.cancel()
    pendingSave = nil
    try? sessionStore.save(
      SessionSnapshot(prompt: prompt, negativePrompt: negativePrompt, parameters: parameters, lockRatio: lockRatio))
  }

  /// True when the server, the model and the session allow a RUN.
  func canRun(with connection: DrawThingsConnection) -> Bool {
    !session.isRunning && !isPreparing && connection.monitor.backend != nil && connection.runBlocker == nil
  }

  /// Starts a RUN, split into its batches (`batchesForRun`). With a random seed, the seed
  /// drawn for the first batch is shown in the Seed field.
  @discardableResult
  func run(with connection: DrawThingsConnection) -> Bool {
    guard canRun(with: connection) else { return false }
    isPreparing = true
    preparation = Task {
      // Memory first: the language model leaves, a server parked for it comes back.
      await languageModel.prepareForRun()
      await connection.ensureServerForRun()
      let inputs = await renderInputs()
      isPreparing = false
      preparation = nil
      guard !Task.isCancelled, let inputs else { return }
      start(with: connection, inputs: inputs)
    }
    return true
  }

  /// Stop (button and ⌘.): ends the preparation that is under way, or the generation.
  func stop() {
    preparation?.cancel()
    session.cancel()
  }

  /// The generation itself, once the memory is ready. The job is composed now, not at the
  /// click: a parked server has no catalog until it is back.
  private func start(with connection: DrawThingsConnection, inputs: GenerationInputs) {
    guard !session.isRunning, let backend = connection.monitor.backend,
      let model = connection.selection.selectedFile,
      RunAvailability.blocker(
        connection: connection.monitor.status, selectedModel: model, catalog: connection.monitor.catalog) == nil
    else { return }
    let batches = JobComposer.batches(
      prompt: prompt, negativePrompt: negativePrompt, model: model, family: family(in: connection),
      parameters: parameters, catalog: connection.monitor.catalog,
      imageStrength: inputs.isEmpty ? nil : control.inputs.effectiveStrength(editModel: isEditModel(in: connection)))
    if parameters.randomSeed, let first = batches.first { parameters.seed = first.parameters.seed }
    session.start(batches, inputs: inputs, backend: backend, monitor: connection.monitor)
  }

  /// The Control tab's images framed to the canvas, decoded away from the main actor. A failure
  /// is shown as the RUN's failure, and nothing starts.
  private func renderInputs() async -> GenerationInputs? {
    let pending = control.pendingInputs(canvasWidth: parameters.width, canvasHeight: parameters.height)
    do {
      return try await Task.detached { try pending.render() }.value
    } catch {
      let text = (error as? ControlError).map(ControlText.error) ?? error.localizedDescription
      session.fail(with: .generationFailed(text))
      return nil
    }
  }

  /// True when the chosen model is an Edit model (the canvas image is the one to modify).
  func isEditModel(in connection: DrawThingsConnection) -> Bool {
    selectedModel(in: connection)?.capabilities.isEditModel ?? false
  }

  /// "Adapt the dimensions": the canvas takes the start image's ratio, with a similar area.
  /// Returns the dimensions it had, to put back.
  @discardableResult
  func adaptDimensionsToImage() -> Size? {
    guard let image = control.inputs.image else { return nil }
    let previous = Size(width: parameters.width, height: parameters.height)
    let adapted = FramingMath.adaptedSize(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, currentWidth: previous.width,
      currentHeight: previous.height)
    restoreDimensions(adapted)
    return previous
  }

  func restoreDimensions(_ size: Size) {
    parameters.width = size.width
    parameters.height = size.height
    if lockRatio { lockedRatio = currentRatio }
  }

  /// "Resume parameters": puts back the prompt, negative prompt, model and parameters of the
  /// batch that made the image (its seed, batch count 1, the LoRAs sent). A ratio lock
  /// follows the resumed size.
  func resume(_ result: GeneratedImage, with connection: DrawThingsConnection) {
    prompt = result.job.prompt
    negativePrompt = result.job.negativePrompt
    parameters = result.job.parameters
    if lockRatio { lockedRatio = currentRatio }
    if let strength = result.job.imageStrength { control.setStrength(strength) }
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
