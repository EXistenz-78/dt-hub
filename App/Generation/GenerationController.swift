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
    didSet {
      scheduleSessionSave()
      contributions?.reconcile()
    }
  }
  /// Sent only when the model's family uses it (`JobComposer`).
  var negativePrompt = "" {
    didSet {
      scheduleSessionSave()
      contributions?.reconcile()
    }
  }
  var parameters = GenerationParameters.default {
    didSet {
      scheduleSessionSave()
      contributions?.reconcile()
    }
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
  /// The RUN. Its pictures go to the open project's folder and its strip is the project's (`ProjectManager`).
  let session: GenerationSession
  let cards = CardExpansionStore(fileURL: CardExpansionStore.defaultFileURL)
  private(set) var outputFolder: URL

  /// The language model, freed when RUN is pressed if the settings say so (spec §9).
  @ObservationIgnored let languageModel: LanguageModelManager
  /// The Control tab's images (tab Control spec): the start image goes with every RUN.
  @ObservationIgnored let control: ControlStore
  /// Enhance Prompt and Generate Prompt. The views read its own observed state (`working`, `failure`).
  @ObservationIgnored let assistant: PromptAssistant
  /// True between pressing RUN and the generation starting: the language model is being freed
  /// and a parked server brought back. Also true all through a pipeline, between its passes.
  private(set) var isPreparing = false
  /// The pass of a plug-in's pipeline that is running (1-based), nil outside one.
  private(set) var pipelinePass: (index: Int, count: Int)?
  /// What the plug-ins contributed (teal fields, conflicts, the pipeline); set by `attach`.
  @ObservationIgnored private(set) var contributions: ContributionStore?

  /// Where a RUN saves: the folder of the open project; nil while no project is open (the RUN is refused then).
  @ObservationIgnored private let projectFolderBox = ProjectFolderBox()
  var projectFolder: URL? {
    didSet { projectFolderBox.folder = projectFolder }
  }
  /// The open project, saved with the session so the next launch knows whose session it was.
  @ObservationIgnored var projectName: String?
  /// True when the session was read back at launch (its project is the one that opens), so the prompt that was not
  /// generated yet is still there and the last image's settings must not overwrite it.
  @ObservationIgnored private(set) var sessionWasRestored = false

  @ObservationIgnored private let outputSettings = OutputSettingsStore()
  @ObservationIgnored private let sessionStore: SessionStore
  @ObservationIgnored private var pendingSave: Task<Void, Never>?
  @ObservationIgnored private var preparation: Task<Void, Never>?

  /// Restores the last prompt and parameters (spec §11) when the session was saved in `restoringProject`, the project
  /// that opens at launch (nil: no project yet, as before projects existed).
  init(
    languageModel: LanguageModelManager, control: ControlStore, restoringProject: String? = nil,
    sessionStore: SessionStore = SessionStore(fileURL: SessionStore.defaultFileURL)
  ) {
    self.languageModel = languageModel
    self.control = control
    session = GenerationSession(store: ProjectImageStore(box: projectFolderBox), history: nil)
    assistant = PromptAssistant(
      resolve: { task, family in
        languageModel.model(for: task, family: family).map {
          PromptAssistant.Choice(
            model: $0, profile: LanguageModelProfile.load(folder: URL(fileURLWithPath: $0.path, isDirectory: true)))
        }
      },
      respond: { prompt, images, options, model throws(LanguageModelError) in
        try await languageModel.respond(to: prompt, images: images, options: options, model: model)
      })
    self.sessionStore = sessionStore
    outputFolder = outputSettings.folder()
    if let snapshot = sessionStore.load(), snapshot.project == restoringProject {
      sessionWasRestored = true
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

  /// The recommended values per model, from the file the app ships (`RecommendedSettings.json`).
  @ObservationIgnored let recommended: RecommendedSettings = {
    guard let url = Bundle.main.url(forResource: "RecommendedSettings", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return .empty }
    return RecommendedSettings(data: data)
  }()

  /// The model chosen in the header: selected, and the tab takes its recommended steps, guidance, sampler and
  /// shift when the model changes (a model the table does not know leaves the values as they are).
  func chooseModel(_ file: String, in connection: DrawThingsConnection) {
    if let values = connection.selection.choose(
      file, applyingTo: parameters, from: recommended, in: connection.monitor.catalog)
    {
      parameters = values
    }
  }

  /// The saved presets (spec §6).
  let presets = PresetStore(folder: PresetStore.defaultFolder)
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

  /// Saves the tab as a preset (parameters but not the size, model, prompt and negative prompt). Whoever does
  /// not want the prompt in it empties the field first. Throws `invalidName` for a name the file system does
  /// not take (empty, "/", ":").
  func savePreset(named name: String, with connection: DrawThingsConnection) throws(PresetError) {
    try presets.save(
      Preset(
        name: name, model: connection.selection.selectedFile ?? "", prompt: prompt, negativePrompt: negativePrompt,
        parameters: parameters))
  }

  /// Puts a preset on the tab: its parameters (the canvas size stays), its prompt and negative prompt when it
  /// has them, its model when it names one.
  /// The preset's file is read now; nil when it was loaded, the reason when it was not.
  func loadPreset(named name: String, with connection: DrawThingsConnection) -> PresetError? {
    do {
      load(try presets.load(named: name), with: connection)
      return nil
    } catch {
      return error
    }
  }

  private func load(_ preset: Preset, with connection: DrawThingsConnection) {
    let load = PresetLoad.of(preset, current: fields, catalog: connection.monitor.catalog)
    parameters = load.parameters
    prompt = load.prompt
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

  /// Enhance Prompt: the language model rewrites the prompt (and the negative prompt, where the family uses one).
  func enhancePrompt(in connection: DrawThingsConnection) async {
    let current = PromptPair(prompt: prompt, negative: negativePrompt)
    if let result = await assistant.enhance(current, family: family(in: connection)) {
      prompt = result.prompt
      negativePrompt = result.negative
    }
  }

  /// Generate Prompt: the language model describes the start image of the Control tab as a prompt.
  func promptFromImage(in connection: DrawThingsConnection) async {
    let url = control.inputs.image.flatMap { control.copyURL(of: $0) }
    let current = PromptPair(prompt: prompt, negative: negativePrompt)
    if let result = await assistant.describe(imageAt: url, current: current, family: family(in: connection)) {
      prompt = result.prompt
      negativePrompt = result.negative
    }
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
      SessionSnapshot(
        prompt: prompt, negativePrompt: negativePrompt, parameters: parameters, lockRatio: lockRatio,
        project: projectName))
  }

  /// True while the project cannot change: a RUN, its preparation or a pipeline is under way.
  func isBusyForProjectSwitch() -> Bool {
    session.isRunning || isPreparing || pipelinePass != nil
  }

  /// Puts a project's last image on the tab: its prompt, negative prompt and parameters and, when the catalog has it, its
  /// model (without the recommended values, which would overwrite the parameters). With nil (a new project, or one
  /// without images) the tab starts from the defaults and the model stays as it is.
  func apply(_ job: GenerationJob?, in connection: DrawThingsConnection) {
    lockRatio = false
    guard let job else {
      prompt = ""
      negativePrompt = ""
      parameters = .default
      return
    }
    prompt = job.prompt
    negativePrompt = job.negativePrompt
    parameters = job.parameters.clamped()
    if connection.monitor.catalog.models.contains(where: { $0.file == job.model }) {
      connection.selection.select(job.model)
    }
  }

  /// True when the server, the model and the session allow a RUN.
  func canRun(with connection: DrawThingsConnection) -> Bool {
    !session.isRunning && !isPreparing && projectFolder != nil && connection.monitor.backend != nil
      && connection.runBlocker == nil
  }

  /// Starts a RUN, split into its batches (`batchesForRun`). With a random seed, the seed
  /// drawn for the first batch is shown in the Seed field. When a plug-in proposed a pipeline, the RUN is
  /// its passes, one after the other.
  @discardableResult
  func run(with connection: DrawThingsConnection) -> Bool {
    guard canRun(with: connection) else { return false }
    // A pipeline reads the presets it names now, once; if one is missing or is not a preset, nothing starts.
    var passes: [PipelineStep]?
    var loadedPresets: [String: Preset] = [:]
    if let pipeline = contributions?.pipeline?.pipeline {
      switch PipelinePresets.load(pipeline, from: presets) {
      case .success(let loaded):
        loadedPresets = loaded
        passes = pipeline.steps
      case .failure(let problem):
        var lines: [String] = []
        if !problem.missing.isEmpty {
          lines.append(String(format: String(localized: "pipeline.missingPreset"), problem.missing.joined(separator: ", ")))
        }
        if !problem.unreadable.isEmpty {
          lines.append(String(format: String(localized: "pipeline.unreadablePreset"), problem.unreadable.joined(separator: ", ")))
        }
        session.fail(with: .generationFailed(lines.joined(separator: "\n")))
        return true
      }
    }
    isPreparing = true
    preparation = Task {
      // Memory first: the language model leaves, a server parked for it comes back.
      await languageModel.prepareForRun()
      await connection.ensureServerForRun()
      if let passes {
        await runPipeline(passes, presets: loadedPresets, with: connection)
        return
      }
      let inputs = await renderInputs(in: connection, parameters: parameters)
      isPreparing = false
      preparation = nil
      guard !Task.isCancelled, let inputs else { return }
      start(with: connection, inputs: inputs)
    }
    return true
  }

  /// The passes of a pipeline, one after the other (plug-in design §7, preset design §4). Each pass runs the
  /// tab's fields with its preset on them; the picture a pass makes can be the next one's start image. A failed or stopped
  /// pass ends the pipeline; the pictures already made stay in the strip.
  private func runPipeline(
    _ passes: [PipelineStep], presets loaded: [String: Preset], with connection: DrawThingsConnection
  ) async {
    defer {
      isPreparing = false
      pipelinePass = nil
      preparation = nil
    }
    var previous: CGImage?
    for (index, pass) in passes.enumerated() {
      guard !Task.isCancelled else { return }
      pipelinePass = (index + 1, passes.count)
      let used = PipelinePresets.fields(for: pass, over: fields, presets: loaded, catalog: connection.monitor.catalog)
      guard let base = await renderInputs(in: connection, parameters: used.parameters) else { return }
      guard !Task.isCancelled, let backend = connection.monitor.backend, let model = connection.selection.selectedFile,
        RunAvailability.blocker(
          connection: connection.monitor.status, selectedModel: model, catalog: connection.monitor.catalog) == nil
      else { return }
      let inputs = PipelineInputs.inputs(
        for: pass, base: base, previousOutput: previous, canvasWidth: used.parameters.width,
        canvasHeight: used.parameters.height, usesMoodboard: FamilyTraits.of(family(in: connection)).usesMoodboard)
      let replacesStart = inputs.image != nil && inputs.image !== base.image
      let batches = JobComposer.batches(
        prompt: used.prompt, negativePrompt: used.negativePrompt, model: model, family: family(in: connection),
        parameters: used.parameters, catalog: connection.monitor.catalog,
        imageStrength: inputs.image == nil ? nil : PipelineInputs.strength(
          tab: control.inputs, replacesStart: replacesStart, editModel: isEditModel(in: connection),
          hasMargins: control.hasMargins(canvasWidth: used.parameters.width, canvasHeight: used.parameters.height)),
        moodboardCount: inputs.hints.count, maskSettings: inputs.mask == nil ? nil : control.inputs.maskSettings)
      let before = session.results.first?.id
      session.start(batches, inputs: inputs, backend: backend, monitor: connection.monitor)
      await session.waitUntilFinished()
      if case .failed = session.phase { return }
      // Stopped from anywhere (the Results window too), or no picture: the pipeline ends here.
      guard !Task.isCancelled, let made = PipelineInputs.output(after: before, in: session.results) else { return }
      previous = made.fileURL.flatMap { PNGImageStore.image(at: $0, maxPixel: 4096) } ?? made.image
    }
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
      imageStrength: inputs.image == nil ? nil : control.inputs.effectiveStrength(
        editModel: isEditModel(in: connection),
        hasMargins: control.hasMargins(canvasWidth: parameters.width, canvasHeight: parameters.height)),
      moodboardCount: inputs.hints.count,
      maskSettings: inputs.mask == nil ? nil : control.inputs.maskSettings)
    if parameters.randomSeed, let first = batches.first { parameters.seed = first.parameters.seed }
    session.start(batches, inputs: inputs, backend: backend, monitor: connection.monitor)
  }

  /// The Control tab's images framed to the canvas, decoded away from the main actor. A failure
  /// is shown as the RUN's failure, and nothing starts.
  private func renderInputs(in connection: DrawThingsConnection, parameters: GenerationParameters) async -> GenerationInputs? {
    // The Moodboard goes only to a model that uses it (the old families would need an adapter).
    let pending = control.pendingInputs(
      canvasWidth: parameters.width, canvasHeight: parameters.height,
      includeMoodboard: FamilyTraits.of(family(in: connection)).usesMoodboard,
      marginFill: control.inputs.marginFill ?? MarginFill.automatic(loras: parameters.loras))
    do {
      var inputs = try await Task.detached { try pending.render() }.value
      inputs.enableInpainting = selectedModel(in: connection)?.capabilities.needsInpaintControl ?? false
      return inputs
    } catch {
      let text = (error as? ControlError).map(ControlText.error) ?? error.localizedDescription
      session.fail(with: .generationFailed(text))
      return nil
    }
  }

  /// What fills the margins of the canvas: the user's choice, or what the LoRAs of the job ask for.
  var marginFill: MarginFill {
    control.inputs.marginFill ?? MarginFill.automatic(loras: parameters.loras)
  }

  /// The plug-ins' contributions land here; the fields leaving their value are told to the store.
  func attach(_ store: ContributionStore) {
    contributions = store
    store.target = self
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
      currentHeight: previous.height, limit: parameters.sizeLimit)
    restoreDimensions(adapted)
    return previous
  }

  /// The Tiled Diffusion switch of the Advanced card: turning it off brings the dimensions back within
  /// 2048, keeping the ratio, and a ratio lock follows the new size.
  func setTiledDiffusion(_ on: Bool) {
    parameters.setTiledDiffusion(on)
    if lockRatio { lockedRatio = currentRatio }
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
    if let settings = result.job.maskSettings { control.setMaskSettings(settings) }
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

/// The folder of the open project, shared with the image store (which saves away from the main actor).
nonisolated final class ProjectFolderBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: URL?

  var folder: URL? {
    get { lock.withLock { value } }
    set { lock.withLock { value = newValue } }
  }
}

/// Saves into the open project's folder, as it is at the moment of saving; without a project nothing is saved.
struct ProjectImageStore: ImageStore {
  let box: ProjectFolderBox

  func save(_ image: CGImage, job: GenerationJob, index: Int, date: Date, elapsed: TimeInterval?) throws -> URL {
    guard let folder = box.folder else { throw ImageStoreError.cannotWrite("no project") }
    return try PNGImageStore(folder: folder).save(image, job: job, index: index, date: date, elapsed: elapsed)
  }
}

// MARK: Plug-in contributions

extension GenerationController: ContributionTarget {
  /// The prompt, the negative prompt and the parameters, as one value. A change keeps a ratio lock on
  /// the new size.
  var fields: GenerationFields {
    get { GenerationFields(prompt: prompt, negativePrompt: negativePrompt, parameters: parameters) }
    set {
      if prompt != newValue.prompt { prompt = newValue.prompt }
      if negativePrompt != newValue.negativePrompt { negativePrompt = newValue.negativePrompt }
      if parameters != newValue.parameters {
        parameters = newValue.parameters
        if lockRatio { lockedRatio = currentRatio }
      }
    }
  }

  var loraFiles: Set<String> { Set(parameters.loras.map(\.file)) }

  func addLoRA(_ lora: LoRASelection) {
    if parameters.loras.contains(where: { $0.file == lora.file }) {
      parameters.updateLoRA(lora)
    } else {
      parameters.loras.append(lora)
    }
  }

  var moodboardIDs: Set<UUID> { Set(control.inputs.moodboard.map(\.id)) }
  var startImageID: UUID? { control.inputs.image?.id }

  func addMoodboardImage(_ image: PluginImageRef, from pluginID: String) throws -> UUID {
    let data = try Self.read(image)
    return try control.addMoodboardImage(data: data, name: image.name, source: .plugin(id: pluginID))
  }

  func removeMoodboardImage(_ id: UUID) { control.removeMoodboardImage(id: id) }

  func setStartImage(_ image: PluginImageRef, from pluginID: String) throws -> UUID {
    let data = try Self.read(image)
    return try control.setImage(data: data, name: image.name, source: .plugin(id: pluginID))
  }

  private static func read(_ image: PluginImageRef) throws -> Data {
    do {
      return try Data(contentsOf: URL(fileURLWithPath: image.path))
    } catch {
      throw ControlError.unreadable(image.name)
    }
  }
}
