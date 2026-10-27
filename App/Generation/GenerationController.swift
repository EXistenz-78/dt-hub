import DTBridge
import CoreGraphics
import Foundation
import HubCore
import ImageIO
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
  /// Incremental mode: the result of a RUN becomes the start image of the next one. Global, remembered.
  var incremental = UserDefaults.standard.bool(forKey: GenerationController.incrementalKey) {
    didSet { UserDefaults.standard.set(incremental, forKey: Self.incrementalKey) }
  }
  static let incrementalKey = "generation.incremental"
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
  /// True from the click on RUN to the end of a pipeline: no pipeline can be sent to RUN meanwhile.
  private(set) var isPipelineRunning = false {
    didSet { contributions?.pipelineLocked = isPipelineRunning }
  }
  /// The model of the pipeline the plug-in is guiding, while it runs: the finished picture it hands over is filed under it.
  @ObservationIgnored private var guidedModelFile: String?
  /// When the passes of that pipeline began: the picture it hands over carries the time the whole pipeline took.
  @ObservationIgnored private var guidedBegan: ContinuousClock.Instant?
  /// How a pipeline the plug-in guides talks to the plug-in; set by the app next to `attach`.
  @ObservationIgnored var guidedChannel: GuidedPluginChannel?
  /// What the plug-ins contributed (teal fields, conflicts, the pipeline); set by `attach`.
  @ObservationIgnored private(set) var contributions: ContributionStore?
  /// The connection a plug-in's `contribute.preset` loads the preset through (its model goes to the header's selection).
  @ObservationIgnored private var presetConnection: DrawThingsConnection?
  /// The presets of the held pipeline, for the CU meter (see `cuPasses`).
  @ObservationIgnored private var cuPresetCache: (pipeline: PluginPipeline, names: [String], presets: [String: Preset])?

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
  @ObservationIgnored var preparation: Task<Void, Never>?

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
      resolve: { task, family, needs in
        languageModel.model(for: task, family: family, needs: needs).map {
          PromptAssistant.Choice(
            model: $0, profile: LanguageModelProfile.load(folder: URL(fileURLWithPath: $0.path, isDirectory: true)))
        }
      },
      respond: { prompt, images, options, model throws(LanguageModelError) in
        try await languageModel.respond(to: prompt, images: images, options: options, model: model)
      },
      library: .live)
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
    Task { await refreshRecommended() }
  }

  /// The recommended values per model: the file the app ships (`RecommendedSettings.json`), with what the list Draw
  /// Things publishes knows of newer models once `refreshRecommended()` has it.
  @ObservationIgnored private(set) var recommended: RecommendedSettings = {
    guard let url = Bundle.main.url(forResource: "RecommendedSettings", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return .empty }
    return RecommendedSettings(data: data)
  }()

  /// The list of official configurations Draw Things publishes, downloaded once per launch and kept on disk.
  private static let liveConfigurations = CachedDownload(
    address: URL(string: "https://models.drawthings.ai/configs.json")!, cacheURL: CachedDownload.supportFile("configs-list.json"),
    isValid: { RecommendedSettings(configurations: $0) != .empty })

  /// Adds to the table the models released after this app was built (at launch; offline, the copy saved last time).
  func refreshRecommended() async {
    guard let data = await Self.liveConfigurations.data() else { return }
    recommended = recommended.merging(RecommendedSettings(configurations: data))
  }

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
  /// The pipelines the user made from the presets (`2026-10-12-pipeline-di-preset-utente-design.md`).
  let userPipelines = UserPipelineStore(folder: UserPipelineStore.defaultFolder)

  /// Makes a saved pipeline the pipeline of RUN, in place of a plug-in's. Returns what went wrong, or nil.
  func selectPipeline(named name: String) -> String? {
    guard !isPipelineRunning else { return nil }
    guard let pipeline = try? userPipelines.load(named: name) else {
      return String(format: String(localized: "pipeline.unreadable"), name)
    }
    let actual = userPipelines.existingName(for: name) ?? name
    contributions?.setUserPipeline(pipeline.pluginPipeline(named: actual), named: actual)
    return nil
  }

  /// After a pipeline or a preset was saved, renamed or deleted: the user's pipeline on RUN follows its file
  /// (`renamedTo` when the file of the pipeline itself was renamed).
  func syncActivePipeline(renamedTo newName: String? = nil) {
    contributions?.syncUserPipeline(with: userPipelines, renamedTo: newName)
  }
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
    // What was just saved is the preset on the tab now.
    presets.markLoaded(name.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// Replaces the file of the preset on the tab (the last one loaded or saved) with the tab as it is now. No-op without one.
  func updateActivePreset(with connection: DrawThingsConnection) throws(PresetError) {
    guard let name = presets.activeName else { return }
    try savePreset(named: name, with: connection)
  }

  /// Puts a preset on the tab: its parameters (the canvas size stays), its prompt and negative prompt when it
  /// has them, its model when it names one.
  /// The preset's file is read now; nil when it was loaded, the reason when it was not.
  func loadPreset(named name: String, with connection: DrawThingsConnection) -> PresetError? {
    do {
      let preset = try presets.load(named: name)
      load(preset, with: connection)
      presets.markLoaded(preset.name)
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

  /// The requests the next RUN would make, for the CU meter: one, or one per pass of the held pipeline. It runs on
  /// every update of the header, so it reads no file but the presets of a newly held pipeline (kept until the
  /// pipeline or the list of presets changes; the pipeline is the held one, which the app keeps in step with the file).
  func cuPasses(in connection: DrawThingsConnection) -> [CUPass] {
    let hasMargins = control.hasMargins(canvasWidth: parameters.width, canvasHeight: parameters.height)
    let summary = CUControlSummary(
      hasImage: control.inputs.image != nil, moodboardCount: control.moodboardURLs.count,
      strength: control.inputs.effectiveStrength(editModel: isEditModel(in: connection), hasMargins: hasMargins))
    var pipeline: PluginPipeline?
    var loaded: [String: Preset] = [:]
    if let held = contributions?.pipeline {
      pipeline = held.pipeline
      let names = presets.names
      if let cache = cuPresetCache, cache.pipeline == held.pipeline, cache.names == names {
        loaded = cache.presets
      } else {
        // A preset that cannot be read leaves only its own pass without an estimate.
        loaded = CUPlanner.availablePresets(for: held.pipeline, from: presets)
        cuPresetCache = (held.pipeline, names, loaded)
      }
    }
    return CUPlanner.passes(
      fields: fields, model: selectedModel(in: connection), control: summary, pipeline: pipeline, presets: loaded,
      catalog: connection.monitor.catalog, headerModel: connection.selection.selectedFile,
      strengthOfPass: { [control] step, replacesStart, editModel, width, height in
        // As `runPipeline` sends it.
        PipelineInputs.strength(
          tab: control.inputs, replacesStart: replacesStart, editModel: editModel,
          hasMargins: control.hasMargins(canvasWidth: width, canvasHeight: height), step: step.strength)
      })
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
    // The start image and the Moodboard pictures that are on (only for a family that reads the Moodboard) go along,
    // so the LLM can see what "image 1", "image 2"… are.
    let images = EnhanceImages(
      start: control.startImageURL,
      references: traits(in: connection).usesMoodboard ? control.moodboardURLs : [])
    if let result = await assistant.enhance(current, family: family(in: connection), images: images) {
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
    session.isRunning || isPreparing || pipelinePass != nil || queueIsRunning()
  }

  /// True while the queue is running its entries; set by the app next to the queue (`GenerationController+Queue.swift`).
  @ObservationIgnored var queueIsRunning: () -> Bool = { false }

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
    var passes: PluginPipeline?
    var loadedPresets: [String: Preset] = [:]
    if let held = contributions?.pipeline {
      var pipeline = held.pipeline
      // The user's pipeline is read from its file now: what RUN executes is what is saved.
      if let name = held.userPipelineName {
        guard let saved = try? userPipelines.load(named: name) else {
          session.fail(with: .generationFailed(String(format: String(localized: "pipeline.unreadable"), name)))
          return true
        }
        pipeline = saved.pluginPipeline(named: name)
        contributions?.setUserPipeline(pipeline, named: name)
      }
      // A guided pipeline has no list of passes: the presets of its estimate are checked now, the others when they come.
      let listed = pipeline.guided.map { PluginPipeline(name: pipeline.name, steps: [$0.estimate]) } ?? pipeline
      switch PipelinePresets.load(listed, from: presets) {
      case .success(let loaded):
        loadedPresets = loaded
        passes = pipeline
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
    isPipelineRunning = passes != nil
    let guidedOwner = contributions?.pipeline?.pluginID
    preparation = Task {
      // Memory first: the language model leaves, a server parked for it comes back.
      await languageModel.prepareForRun()
      await connection.ensureServerForRun()
      if let passes {
        if passes.guided != nil, let guidedOwner {
          _ = await runGuidedPipeline(passes, pluginID: guidedOwner, presets: loadedPresets, with: connection)
          return
        }
        let made = await runPipeline(passes, presets: loadedPresets, with: connection)
        if incremental, let made, !Task.isCancelled { await useAsStart(made) }
        return
      }
      let inputs = await renderInputs(in: connection, parameters: parameters, model: selectedModel(in: connection))
      isPreparing = false
      preparation = nil
      guard !Task.isCancelled, let inputs else { return }
      let before = session.results.first?.id
      start(with: connection, inputs: inputs)
      guard incremental else { return }
      await session.waitUntilFinished()
      if let made = IncrementalRun.output(
        enabled: incremental, phase: session.phase, stopped: session.lastRunWasStopped, before: before,
        results: session.results)
      {
        await useAsStart(made)
      }
    }
    return true
  }

  /// The passes of a pipeline, one after the other (plug-in design §7, preset design §4). Each pass runs the
  /// tab's fields with its preset on them; the picture a pass makes can be the next one's start image. A failed or stopped
  /// pass ends the pipeline; the pictures already made stay in the strip. Returns the picture of the last pass when
  /// every pass finished (nil when the pipeline ended early or was stopped).
  private func runPipeline(
    _ pipeline: PluginPipeline, presets loaded: [String: Preset], with connection: DrawThingsConnection
  ) async -> GeneratedImage? {
    defer {
      isPreparing = false
      pipelinePass = nil
      preparation = nil
      isPipelineRunning = false
    }
    let passes = pipeline.steps
    // Checked here and not at the click: a server parked for the language model has no catalog until it is back.
    let missing = PipelinePresets.missingModels(in: pipeline, presets: loaded, catalog: connection.monitor.catalog)
    guard missing.isEmpty else {
      if !Task.isCancelled {
        session.fail(
          with: .generationFailed(String(format: String(localized: "pipeline.missingModel"), missing.joined(separator: ", "))))
      }
      return nil
    }
    var previous: CGImage?
    var previousSize: Size?
    var lastMade: GeneratedImage?
    for (index, pass) in passes.enumerated() {
      guard !Task.isCancelled else { return nil }
      pipelinePass = (index + 1, passes.count)
      guard
        let run = await runPass(
          pass, presets: loaded, previous: previous, previousSize: previousSize, intermediate: nil, with: connection),
        let made = run.made
      else { return nil }
      previousSize = run.size
      lastMade = run.wasStopped ? nil : made
      previous = made.fileURL.flatMap { PNGImageStore.image(at: $0, maxPixel: 4096) } ?? made.image
    }
    return lastMade
  }

  /// What one pass left: the picture it made (`made`, in the strip) or, for a pass of a pipeline the plug-in guides, the
  /// file of its picture (`intermediate`); the size it ran at; whether Stop ended it.
  private struct PassRun {
    var made: GeneratedImage?
    var intermediate: IntermediateResult?
    var size: Size
    var wasStopped: Bool
  }

  /// One pass: the tab's fields with the pass's preset on them, the inputs the pass asks for, one run. Nil when the pass
  /// could not run or was stopped (the phase of the session says which). With `intermediate` the pass is one the plug-in
  /// handed over (own image, mask and size, and the picture goes to that file, not to the strip).
  private func runPass(
    _ pass: PipelineStep, presets loaded: [String: Preset], previous: CGImage?, previousSize: Size?, intermediate: URL?,
    with connection: DrawThingsConnection
  ) async -> PassRun? {
    // A pass the plug-in handed over starts from the tab without its LoRAs and with one picture per run.
    let tab = intermediate != nil ? GuidedPassInputs.baseFields(from: fields, size: pass.size) : fields
    var used = PipelinePresets.fields(for: pass, over: tab, presets: loaded, catalog: connection.monitor.catalog)
    // A user's pipeline: from the second pass on, the size is the previous pass's, multiplied by the pass's scale.
    if pass.usesPresetModel, let previousSize {
      let size = PipelineSizes.scaled(previousSize, by: pass.scale, limit: used.parameters.sizeLimit)
      used.parameters.width = size.width
      used.parameters.height = size.height
    }
    if intermediate != nil, let size = pass.size {
      used.parameters.width = size.width
      used.parameters.height = size.height
    }
    let ranAt = Size(width: used.parameters.width, height: used.parameters.height)
    // The model of the pass: its preset's in a user's pipeline, the header's otherwise. Everything below uses it.
    let file = PipelinePresets.model(for: pass, presets: loaded, header: connection.selection.selectedFile)
    let passModel = file.flatMap { connection.monitor.catalog.model(forFile: $0) }
    let family = passModel?.family
    let inputs: GenerationInputs
    var replacesStart = false
    if intermediate != nil {
      switch GuidedPassInputs.inputs(for: pass, enableInpainting: passModel?.capabilities.needsInpaintControl ?? false) {
      case .success(let value): inputs = value
      case .failure(let error):
        session.fail(
          with: .generationFailed(String(format: String(localized: "pipeline.guided.badPass"), String(describing: error))))
        return nil
      }
      replacesStart = true
    } else {
      guard let base = await renderInputs(in: connection, parameters: used.parameters, model: passModel) else { return nil }
      inputs = PipelineInputs.inputs(
        for: pass, base: base, previousOutput: previous, canvasWidth: used.parameters.width,
        canvasHeight: used.parameters.height, usesMoodboard: FamilyTraits.of(family).usesMoodboard)
      replacesStart = inputs.image != nil && inputs.image !== base.image
    }
    guard !Task.isCancelled, let backend = connection.monitor.backend, let model = file,
      RunAvailability.blocker(
        connection: connection.monitor.status, selectedModel: model, catalog: connection.monitor.catalog) == nil
    else { return nil }
    let strength: Double? =
      inputs.image == nil
      ? nil
      : intermediate != nil
        ? (pass.strength ?? 1)
        : PipelineInputs.strength(
          tab: control.inputs, replacesStart: replacesStart, editModel: passModel?.capabilities.isEditModel ?? false,
          hasMargins: control.hasMargins(canvasWidth: used.parameters.width, canvasHeight: used.parameters.height),
          step: pass.strength)
    let batches = JobComposer.batches(
      prompt: used.prompt, negativePrompt: used.negativePrompt, model: model, family: family,
      parameters: used.parameters, catalog: connection.monitor.catalog, imageStrength: strength,
      moodboardCount: inputs.hints.count,
      maskSettings: inputs.mask == nil
        ? nil : (intermediate != nil ? (pass.maskSettings ?? control.inputs.maskSettings) : control.inputs.maskSettings))
    let before = session.results.first?.id
    session.start(batches, inputs: inputs, backend: backend, monitor: connection.monitor, intermediate: intermediate)
    await session.waitUntilFinished()
    if case .failed = session.phase { return nil }
    if intermediate != nil {
      // Stopped from anywhere, or no picture: the pipeline ends here.
      guard !Task.isCancelled, let result = session.intermediateResult else { return nil }
      return PassRun(made: nil, intermediate: result, size: ranAt, wasStopped: session.lastRunWasStopped)
    }
    // Stopped from anywhere (the Results window too), or no picture: the pipeline ends here.
    guard !Task.isCancelled, let made = PipelineInputs.output(after: before, in: session.results) else { return nil }
    return PassRun(made: made, intermediate: nil, size: ranAt, wasStopped: session.lastRunWasStopped)
  }

  /// A pipeline the plug-in guides (spec 2026-10-18 §5, §6): for each pass the plug-in is asked for the next one
  /// (`session.next`), the app runs it, and the picture goes back to the plug-in as a file. The pictures of the passes are
  /// not results; the plug-in makes the result.
  private func runGuidedPipeline(
    _ pipeline: PluginPipeline, pluginID: String, presets loaded: [String: Preset], with connection: DrawThingsConnection
  ) async -> GeneratedImage? {
    defer {
      isPreparing = false
      pipelinePass = nil
      preparation = nil
      isPipelineRunning = false
    }
    guard let channel = guidedChannel, let guided = pipeline.guided else {
      session.fail(with: .generationFailed(String(localized: "pipeline.pluginClosed")))
      return nil
    }
    let folder = channel.sessionFolder()
    defer { channel.removeSessionFolder(folder) }
    let startModel = connection.selection.selectedFile
    guidedModelFile = startModel
    guidedBegan = .now
    defer {
      guidedModelFile = nil
      guidedBegan = nil
      // The session is over, whatever the reason: the pipeline goes from the Run button.
      contributions?.finishedGuidedPipeline()
    }
    var known = loaded
    let driver = GuidedSessionDriver(
      passes: guided.passes, tileLimit: parameters.sizeLimit,
      ask: { await channel.request($0, pluginID, .seconds(60)) },
      runPass: { [self] step, index in
        guard connection.selection.selectedFile == startModel else {
          return .failed(String(localized: "pipeline.modelChanged"))
        }
        if !step.preset.isEmpty, known[step.preset] == nil {
          switch PipelinePresets.load(PluginPipeline(steps: [step]), from: presets) {
          case .success(let more): known.merge(more) { _, new in new }
          case .failure(let problem):
            return .failed(String(format: String(localized: "pipeline.missingPreset"), (problem.missing + problem.unreadable).joined(separator: ", ")))
          }
        }
        let target = folder.appendingPathComponent("pass-\(index).png")
        guard
          let run = await runPass(
            step, presets: known, previous: nil, previousSize: nil, intermediate: target, with: connection)
        else {
          if case .failed(let error) = session.phase { return .failed(String(describing: error)) }
          return .stopped
        }
        guard !run.wasStopped, let result = run.intermediate else { return .stopped }
        return .made(result.url, width: result.width, height: result.height)
      },
      end: { _ = await channel.request($0, pluginID, .seconds(5)) },
      progress: { [self] index, count in pipelinePass = (index, count) })
    switch await driver.run() {
    case .finished, .stopped: break
    case .closed: session.fail(with: .generationFailed(String(localized: "pipeline.pluginClosed")))
    case .failed(let reason):
      if case .failed = session.phase { break }
      session.fail(with: .generationFailed(reason))
    }
    return nil
  }

  /// Makes a result the start image of the Control tab, as "Use as image" in the Results window does.
  private func useAsStart(_ result: GeneratedImage) async {
    do throws(ControlError) {
      if let url = result.fileURL {
        try await control.setImage(fileURL: url, source: .result)
      } else {
        try control.setImage(result.image, name: String(localized: "results.unsaved.name"), source: .result)
      }
    } catch {
      session.fail(with: .generationFailed(ControlText.error(error)))
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
  /// `model` is the model the job runs with: the header's, or the one of a pipeline's pass.
  private func renderInputs(
    in connection: DrawThingsConnection, parameters: GenerationParameters, model: CatalogModel?
  ) async -> GenerationInputs? {
    // The Moodboard goes only to a model that uses it (the old families would need an adapter).
    let pending = control.pendingInputs(
      canvasWidth: parameters.width, canvasHeight: parameters.height,
      includeMoodboard: FamilyTraits.of(model?.family).usesMoodboard,
      marginFill: control.inputs.marginFill ?? MarginFill.automatic(loras: parameters.loras))
    do {
      var inputs = try await Task.detached { try pending.render() }.value
      inputs.enableInpainting = model?.capabilities.needsInpaintControl ?? false
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
  func attach(_ store: ContributionStore, connection: DrawThingsConnection) {
    contributions = store
    presetConnection = connection
    store.target = self
    store.pipelineLocked = isPipelineRunning
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

  /// The HiRes (beta) checkbox of the Dimensions card: turning it off brings the dimensions back within 2048.
  func setHighRes(_ on: Bool) {
    parameters.setHighRes(on)
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
    // The layout of Draw Things, so the tools made for its pictures read DT Hub's too.
    return try PNGImageStore(
      folder: folder, metadata: DrawThingsMetadata.comment, description: DrawThingsMetadata.description)
      .save(image, job: job, index: index, date: date, elapsed: elapsed)
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

  /// A plug-in's `contribute.preset`: the saved preset loaded as the Preset menu loads it.
  func applyPreset(named name: String) -> String? {
    guard let connection = presetConnection else { return "the app is not ready." }
    switch loadPreset(named: name, with: connection) {
    case nil: return nil
    case .notFound?: return "there is no preset named “\(name)”."
    case .unreadable?: return "the file of the preset “\(name)” cannot be read."
    case .some: return "the preset “\(name)” cannot be used."
    }
  }

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

  func setStrength(_ value: Double) { control.setStrength(value) }

  /// The plug-in's drawing becomes the Brush layer: read, stretched to the size of the layer, one step of Control's history.
  func setPaint(_ image: PluginImageRef) throws {
    let data = try Self.read(image)
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), let picture = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw ControlError.unreadable(image.name) }
    guard let size = control.maskSize else { return }
    guard let bitmap = PaintBitmap.fitted(from: picture, width: size.width, height: size.height) else {
      throw ControlError.unreadable(image.name)
    }
    try control.commitPaint(bitmap)
  }

  /// A picture the plug-in finished (a composed enlargement) becomes a result: saved in the project's folder and put in the
  /// strip, filed under the model of the pipeline that made it, with `description` where the prompt would be. Only while
  /// a pipeline the plug-in guides is running.
  func addResult(_ image: PluginImageRef, description: String) throws {
    guard let model = ResultFiling.model(guided: guidedModelFile, header: presetConnection?.selection.selectedFile) else {
      throw ControlError.unreadable(image.name)
    }
    let url = URL(fileURLWithPath: image.path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { throw ControlError.unreadable(image.name) }
    var shown = parameters
    shown.width = width
    shown.height = height
    shown.loras = []
    shown.batchSize = 1
    shown.batchCount = 1
    let job = GenerationJob(prompt: description, model: model, parameters: shown)
    let elapsed = guidedBegan.map { start -> TimeInterval in
      let took = start.duration(to: .now)
      return Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
    }
    Task { _ = await session.adopt(fileAt: url, job: job, elapsed: elapsed) }
  }

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

/// What the controller needs from the plug-in registry to run a pipeline the plug-in guides.
struct GuidedPluginChannel {
  /// A message to the plug-in and its answer (nil: none within the time).
  var request: @MainActor (Data, String, Duration) async -> Data?
  /// A new folder for the pictures of one session.
  var sessionFolder: @MainActor () -> URL
  var removeSessionFolder: @MainActor (URL) -> Void
}
