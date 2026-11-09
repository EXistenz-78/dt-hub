import CoreGraphics
import Foundation
import HubCore
import HubKit
import HubMCP
import ImageIO
import UniformTypeIdentifiers

/// The app's side of the MCP server (spec 2026-11-08 §3): what an agent reads and does, on the Generation tab, the queue,
/// the contributions and the results. Edits go through `ContributionStore` as the contributor `agentID`, so the fields an
/// agent changes show in teal with the value they had.
@MainActor
final class AppAgentHost: AgentHost {
  static let agentID = "dthub.remote-agent"
  static let pipelineName = "Agent pipeline"

  private let generation: GenerationController
  private let connection: DrawThingsConnection
  private let queueStore: QueueStore
  private let queueRunner: QueueRunner
  private let languageModel: LanguageModelManager
  private let pluginRegistry: PluginRegistry
  private let projectManager: ProjectManager
  var onJobEvent: ((AgentJobEvent) -> Void)?
  private var watcher: Task<Void, Never>?

  init(
    generation: GenerationController, connection: DrawThingsConnection, queueStore: QueueStore, queueRunner: QueueRunner,
    languageModel: LanguageModelManager, plugins: PluginRegistry, projects: ProjectManager
  ) {
    self.generation = generation
    self.connection = connection
    self.queueStore = queueStore
    self.queueRunner = queueRunner
    self.languageModel = languageModel
    self.pluginRegistry = plugins
    self.projectManager = projects
  }

  // MARK: Reading

  var currentFamily: String? { generation.family(in: connection) }

  private struct SpecialistKey: Equatable {
    var family: String
    var settings: LanguageModelSettings
  }
  /// Looking for the specialist scans the LLM folder on disk: the answer is kept until the family or the language-model
  /// settings change (or two minutes pass, for a model installed meanwhile).
  private var specialistCache: (key: SpecialistKey, at: Date, value: Bool)?

  var hasSpecialistLLM: Bool {
    guard let family = currentFamily else { return false }
    let key = SpecialistKey(family: family, settings: languageModel.settings)
    if let cached = specialistCache, cached.key == key, Date().timeIntervalSince(cached.at) < 120 { return cached.value }
    let value = findSpecialistLLM(family: family)
    specialistCache = (key, Date(), value)
    return value
  }

  private func findSpecialistLLM(family: String) -> Bool {
    guard case .success(let model) = languageModel.model(for: .enhance, family: family) else { return false }
    if case .family(let key)? = languageModel.settings.assignments[model.name]?.family, key == family { return true }
    return LanguageModelProfile.load(folder: URL(fileURLWithPath: model.path, isDirectory: true)).pup != nil
  }

  func state() -> AgentState {
    var state = AgentState()
    let model = generation.selectedModel(in: connection)
    state.modelFile = model?.file
    state.modelName = model?.name
    state.family = currentFamily
    state.prompt = generation.prompt
    state.negativePrompt = generation.negativePrompt
    let p = generation.parameters
    state.fields = [
      "width": .int(p.width), "height": .int(p.height), "steps": .int(p.steps), "guidanceScale": .double(p.guidanceScale),
      "shift": .double(p.shift), "resolutionDependentShift": .bool(p.resolutionDependentShift),
      "cfgZeroStar": .bool(p.cfgZeroStar), "cfgZeroInitSteps": .int(p.cfgZeroInitSteps), "seed": .int(Int(p.seed)),
      "randomSeed": .bool(p.randomSeed), "sampler": .string(p.sampler.displayName), "batchSize": .int(p.batchSize),
      "batchCount": .int(p.batchCount), "highRes": .bool(p.highRes),
    ]
    state.loras = p.loras.map { AgentLoRAUse(file: $0.file, weight: $0.weight) }
    state.moodboardCount = generation.control.moodboardURLs.count
    state.hasStartImage = generation.control.inputs.image != nil
    if state.hasStartImage {
      state.strength = generation.control.inputs.effectiveStrength(
        editModel: generation.isEditModel(in: connection),
        hasMargins: generation.control.hasMargins(canvasWidth: p.width, canvasHeight: p.height))
    }
    state.isGenerating = isBusy
    state.incremental = generation.incremental
    state.selectedPipeline = generation.contributions?.pipeline.map { $0.userPipelineName ?? $0.pipeline.name }
    return state
  }

  func models() -> [AgentModel] {
    connection.monitor.catalog.models.map {
      AgentModel(file: $0.file, name: $0.name, family: $0.family ?? "", kind: $0.isRemote ? "cloud" : "local")
    }
  }

  func loras() -> [AgentLoRA] {
    connection.monitor.catalog.loras.map { AgentLoRA(file: $0.file, name: $0.name, families: $0.family.map { [$0] } ?? []) }
  }

  func presetNames() -> [String] { generation.presets.names }
  func pipelineNames() -> [String] { generation.userPipelines.names }

  func promptGuide(family: String) -> String? {
    guard let guide = PromptLibrary.live.family(family) else { return nil }
    return """
      \(guide.label)
      Uses a negative prompt: \(guide.negative ? "yes" : "no")
      Length: \(guide.words) words (at most \(guide.maxWords))

      \(guide.notes)
      """
  }

  func results() -> [AgentResult] {
    generation.session.results.compactMap { result in
      result.fileURL.map {
        AgentResult(id: result.id.uuidString, path: $0.path, prompt: result.job.prompt, model: result.job.model, date: result.date)
      }
    }
  }

  func resultImage(id: String, maxSide: Int) -> Data? {
    guard let result = generation.session.results.first(where: { $0.id.uuidString == id }) else { return nil }
    return Self.png(of: result.image, maxSide: maxSide)
  }

  func queueEntries() -> [AgentQueueEntry] {
    queueStore.entries.map {
      AgentQueueEntry(id: $0.id, summary: "\($0.preset.model) · \($0.preset.prompt.prefix(80))", status: "\($0.status)")
    }
  }

  func plugins() -> [AgentPlugin] {
    let family = currentFamily
    let edit = generation.isEditModel(in: connection)
    return pluginRegistry.entries.map { entry in
      var reason: String?
      if case .failed(let error) = entry.state { reason = "Failed to load: \(error)" }
      else if let manifest = entry.manifest, !manifest.supports(family: family, isEditModel: edit) {
        reason = "Not compatible with the current model."
      }
      return AgentPlugin(id: entry.id, name: entry.name, isActive: entry.isActive, unavailableReason: reason)
    }
  }

  func serverStatus() -> AgentServerStatus {
    let managedNow = connection.otherServerMode == .attach
    return AgentServerStatus(
      mode: managedNow ? "managed" : "attach", connected: connection.monitor.status == .connected,
      detail: "\(connection.indicator)", otherMode: managedNow ? "attach" : "managed", canSwitch: connection.canSwitchServer,
      cannotSwitchReason: connection.canSwitchServer
        ? nil : "The settings of the other server are not valid: they are set in DT Hub › Settings › Draw Things.")
  }

  func advancedValues() -> [String: AgentValue] {
    guard let data = try? JSONEncoder().encode(generation.parameters.advanced),
      let values = try? JSONDecoder().decode([String: AgentValue].self, from: data)
    else { return [:] }
    return values
  }

  func advancedApplicable() -> [String] {
    let model = generation.selectedModel(in: connection)
    return AdvancedField.allCases.filter { $0.isShown(for: model, sampler: generation.parameters.sampler) }.map(\.rawValue)
  }

  func projects() -> [AgentProject] {
    projectManager.projects.map { AgentProject(name: $0.name, isCurrent: $0.name == projectManager.current?.name) }
  }

  // MARK: Editing

  private func contribute(_ contribution: PluginContribution) throws(AgentError) {
    guard let store = generation.contributions else { throw .unavailable("The app is not ready.") }
    let problems = store.receive(contribution, from: Self.agentID)
    if !problems.isEmpty { throw .invalid(problems.joined(separator: " ")) }
  }

  private func overlayValue(_ key: String, _ value: AgentValue) throws(AgentError) -> (ContributionField, FieldValue) {
    guard let field = ContributionField(rawValue: key) else { throw .invalid("Unknown field '\(key)'.") }
    if field == .sampler {
      switch value {
      case .int(let raw):
        guard Sampler(rawValue: raw) != nil else { throw .invalid("Unknown sampler \(raw).") }
        return (field, .int(raw))
      case .string(let name):
        let wanted = name.lowercased()
        guard let sampler = Sampler.allCases.first(where: { $0.displayName.lowercased() == wanted }) else {
          throw .invalid("Unknown sampler '\(name)'. Valid: \(Sampler.allCases.map(\.displayName).joined(separator: ", ")).")
        }
        return (field, .int(sampler.rawValue))
      default: throw .invalid("Field 'sampler' takes a sampler name.")
      }
    }
    switch value {
    case .string(let v): return (field, .text(v))
    case .int(let v): return (field, .int(v))
    case .double(let v): return (field, .double(v))
    case .bool(let v): return (field, .bool(v))
    }
  }

  func setFields(_ fields: [String: AgentValue]) throws(AgentError) -> [String] {
    var overlay: [ContributionField: FieldValue] = [:]
    for (key, value) in fields {
      let (field, converted) = try overlayValue(key, value)
      overlay[field] = converted
    }
    try contribute(PluginContribution(fields: FieldOverlay(overlay)))
    // A field another plug-in holds with a different value becomes a conflict the user decides: it is not applied.
    let marks = generation.contributions?.marks ?? [:]
    return fields.keys.filter { key in
      ContributionField(rawValue: key).map { marks[$0]?.pluginID == Self.agentID } ?? false
    }.sorted()
  }

  func addLoRA(file: String, weight: Double) throws(AgentError) {
    guard let lora = connection.monitor.catalog.loras.first(where: { $0.file == file }) else {
      throw .invalid("Unknown LoRA '\(file)'. Use a file from list_loras.")
    }
    try contribute(PluginContribution(loras: [LoRASelection(file: file, weight: weight, trigger: lora.trigger)]))
  }

  func setLoRAWeight(file: String, weight: Double) throws(AgentError) {
    guard let current = generation.parameters.loras.first(where: { $0.file == file }) else {
      throw .invalid("The LoRA '\(file)' is not on the tab; add it first.")
    }
    try contribute(PluginContribution(loras: [LoRASelection(file: file, weight: weight, mode: current.mode, trigger: current.trigger)]))
  }

  func removeLoRA(file: String) throws(AgentError) {
    guard generation.parameters.loras.contains(where: { $0.file == file }) else {
      throw .invalid("The LoRA '\(file)' is not on the tab.")
    }
    generation.removeLoRA(file)
  }

  private func reference(for image: AgentImage) throws(AgentError) -> PluginImageRef {
    switch image.source {
    case .path(let path):
      return PluginImageRef(name: URL(fileURLWithPath: path).lastPathComponent, path: path)
    case .result(let id):
      guard let url = generation.session.results.first(where: { $0.id.uuidString == id })?.fileURL else {
        throw .invalid("The result '\(id)' has no picture file.")
      }
      return PluginImageRef(name: url.lastPathComponent, path: url.path)
    }
  }

  func setMoodboard(_ items: [AgentImage], replace: Bool) async throws(AgentError) -> Int {
    var refs: [PluginImageRef] = []
    for item in items { refs.append(try reference(for: item)) }
    var replaced = 0
    if replace {
      replaced = generation.control.inputs.moodboard.count
      generation.control.clearMoodboard()
    }
    for ref in refs {
      do { _ = try generation.addMoodboardImage(ref, from: Self.agentID) } catch { throw .invalid("\(ref.name): \(error)") }
    }
    return replaced
  }

  func setStartImage(_ image: AgentImage) async throws(AgentError) {
    try contribute(PluginContribution(startImage: try reference(for: image)))
  }

  func setIncremental(_ on: Bool) { generation.incremental = on }

  func setAdvanced(_ values: [String: AgentValue]) throws(AgentError) -> [String] {
    var current = advancedValues()
    var requested: [String: Double] = [:]
    for (key, new) in values.sorted(by: { $0.key < $1.key }) {
      guard let old = current[key] else {
        throw .invalid("Unknown advanced field '\(key)'. Valid fields: \(current.keys.sorted().joined(separator: ", ")).")
      }
      switch (old, new) {
      case (.bool, .bool), (.string, .string): current[key] = new
      case (.int, .int), (.int, .double), (.double, .int), (.double, .double):
        // A number that is whole is read back as an integer whichever it was: the type is checked after the round trip.
        var number = 0.0
        if case .int(let v) = new { number = Double(v) } else if case .double(let v) = new { number = v }
        requested[key] = number
        current[key] = number == number.rounded() && abs(number) < 1e15 ? .int(Int(number)) : .double(number)
      default: throw .invalid("Field '\(key)' has the wrong type.")
      }
    }
    guard let data = try? JSONEncoder().encode(current),
      let merged = try? JSONDecoder().decode(AdvancedParameters.self, from: data)
    else { throw .invalid("The values could not be applied.") }
    // A fractional number written into a whole-number field would have fallen back to the default: say so.
    if let back = try? JSONEncoder().encode(merged), let after = try? JSONDecoder().decode([String: AgentValue].self, from: back) {
      for (key, number) in requested {
        var got = 0.0
        if case .int(let v)? = after[key] { got = Double(v) } else if case .double(let v)? = after[key] { got = v }
        if abs(got - number) > 1e-9 { throw .invalid("Field '\(key)' takes a whole number.") }
      }
    }
    generation.parameters.advanced = merged.clamped()
    return values.keys.sorted()
  }

  func clearMoodboard() throws(AgentError) -> Int {
    let count = generation.control.inputs.moodboard.count
    generation.control.clearMoodboard()
    return count
  }

  func clearStartImage() throws(AgentError) {
    guard generation.control.inputs.image != nil else { throw .invalid("There is no start image.") }
    generation.control.removeImage()
  }

  func clearPipeline() throws(AgentError) {
    if isBusy { throw .busy(jobID: nil) }
    generation.contributions?.removePipeline()
  }

  func setStrength(_ value: Double) throws(AgentError) {
    guard generation.control.inputs.image != nil else { throw .invalid("There is no start image; set one first.") }
    generation.setStrength(value)
  }

  func loadPreset(named name: String) -> String? {
    guard let store = generation.contributions else { return "The app is not ready." }
    let problems = store.receive(PluginContribution(preset: name), from: Self.agentID)
    return problems.isEmpty ? nil : problems.joined(separator: " ")
  }

  func savePreset(named name: String) throws(AgentError) {
    do { try generation.savePreset(named: name, with: connection) } catch { throw .invalid("\(error)") }
  }

  // MARK: Controlling

  private var isBusy: Bool {
    generation.session.isRunning || generation.isPreparing || generation.isPipelineRunning || queueRunner.isRunning
  }

  func setModel(file: String) throws(AgentError) {
    if isBusy { throw .busy(jobID: nil) }
    generation.chooseModel(file, in: connection)
  }

  func switchServer() async throws(AgentError) -> AgentServerStatus {
    if isBusy { throw .busy(jobID: nil) }
    guard connection.canSwitchServer else { throw .unavailable(serverStatus().cannotSwitchReason ?? "Cannot switch server.") }
    await connection.switchServer()
    // The new server may take a while to start and load: wait until it answers (or a minute passes).
    for _ in 0..<60 {
      if connection.monitor.status == .connected { break }
      await connection.monitor.refresh()
      if connection.monitor.status == .connected { break }
      try? await Task.sleep(for: .seconds(1))
    }
    return serverStatus()
  }

  func openProject(name: String) async throws(AgentError) {
    guard let project = projectManager.projects.first(where: { $0.name == name }) else {
      throw .invalid("No project named '\(name)'. Use a name from list_projects.")
    }
    await projectManager.open(project)
    if projectManager.lastError != nil { throw .busy(jobID: nil) }
  }

  func createProject(name: String) async throws(AgentError) {
    if await projectManager.create(named: name) { return }
    throw .invalid("The project '\(name)' could not be created (the name may be taken or not allowed).")
  }

  private var imagesPerPass: Int { max(1, generation.parameters.batchCount * generation.parameters.batchSize) }
  private var modelLabel: String { generation.selectedModel(in: connection)?.name ?? "the current model" }

  private func plan(passes: Int) -> AgentRunPlan {
    let images = max(1, passes) * imagesPerPass
    return AgentRunPlan(images: images, estimatedCU: nil, summary: "\(images) image(s) with \(modelLabel)")
  }

  func planRun() -> AgentRunPlan {
    plan(passes: generation.contributions?.pipeline?.pipeline.passCount ?? 1)
  }

  func planPipeline(named name: String) throws(AgentError) -> AgentRunPlan {
    if name == Self.pipelineName, let held = generation.contributions?.pipeline, held.pluginID == Self.agentID {
      return plan(passes: held.pipeline.passCount)
    }
    guard let saved = try? generation.userPipelines.load(named: name) else { throw .invalid("Unknown pipeline '\(name)'.") }
    return plan(passes: saved.pluginPipeline(named: name).passCount)
  }

  func planQueue() -> AgentRunPlan {
    let images = queueStore.entries.filter { $0.status == .pending }.reduce(0) { total, entry in
      let passes: Int
      switch entry.pipeline {
      case nil: passes = 1
      case .user(let name)?: passes = (try? generation.userPipelines.load(named: name))?.pluginPipeline(named: name).passCount ?? 1
      case .plugin(_, _, let steps)?: passes = steps.count
      case .guided(_, _, let count, _)?: passes = count
      }
      return total + max(1, passes) * max(1, entry.preset.parameters.batchCount * entry.preset.parameters.batchSize)
    }
    return AgentRunPlan(images: images, estimatedCU: nil, summary: "\(images) queued image(s)")
  }

  private func ensureCanStart() throws(AgentError) {
    if isBusy { throw .busy(jobID: nil) }
    if !generation.canRun(with: connection) {
      throw .unavailable(connection.runBlocker.map { "\($0)" } ?? "DT Hub cannot run now (no project open, or no Draw Things server).")
    }
  }

  func startRun() throws(AgentError) {
    try ensureCanStart()
    let total = planRun().images
    let baseline = generation.session.results.first?.id
    guard generation.run(with: connection) else { throw .unavailable("DT Hub cannot run now.") }
    watch(total: total, since: baseline)
  }

  func startPipeline(named name: String) throws(AgentError) {
    try ensureCanStart()
    let total = try planPipeline(named: name).images
    if !(name == Self.pipelineName && generation.contributions?.pipeline?.pluginID == Self.agentID) {
      if let problem = generation.selectPipeline(named: name) { throw .invalid(problem) }
    }
    let baseline = generation.session.results.first?.id
    guard generation.run(with: connection) else { throw .unavailable("DT Hub cannot run now.") }
    watch(total: total, since: baseline)
  }

  func startQueue() throws(AgentError) {
    if isBusy { throw .busy(jobID: nil) }
    guard queueStore.firstPending != nil else { throw .invalid("The queue has no pending entries.") }
    let total = planQueue().images
    let baseline = generation.session.results.first?.id
    queueRunner.start()
    watch(total: total, since: baseline)
  }

  func stop() {
    // The tool reports the stop itself: a late event of the old watcher must not touch the next job.
    watcher?.cancel()
    generation.stop()
  }

  func stopQueue() {
    watcher?.cancel()
    queueRunner.stop()
  }

  func definePipeline(steps: [AgentPipelineStep]) throws(AgentError) -> String {
    var pipelineSteps: [PipelineStep] = []
    for (index, step) in steps.enumerated() {
      var overlay: [ContributionField: FieldValue] = [:]
      if let prompt = step.prompt { overlay[.prompt] = .text(prompt) }
      if let negative = step.negativePrompt { overlay[.negativePrompt] = .text(negative) }
      for (key, value) in step.fields {
        let (field, converted) = try overlayValue(key, value)
        overlay[field] = converted
      }
      pipelineSteps.append(PipelineStep(title: "Step \(index + 1)", fields: FieldOverlay(overlay)))
    }
    try contribute(PluginContribution(pipeline: PluginPipeline(name: Self.pipelineName, steps: pipelineSteps)))
    return Self.pipelineName
  }

  func queueAdd() async throws(AgentError) -> UUID {
    // A running queue takes new entries at once: they would run without the budget being charged.
    if queueRunner.isRunning { throw .busy(jobID: nil) }
    let (entry, problem) = await generation.captureQueueEntry(in: connection, store: queueStore)
    guard let entry else { throw .unavailable(problem ?? "The tab cannot be queued.") }
    queueStore.add(entry)
    return entry.id
  }

  func queueRemove(id: UUID) throws(AgentError) {
    guard queueStore.entries.contains(where: { $0.id == id }) else { throw .invalid("No such queue entry.") }
    queueStore.remove(id: id)
  }

  func enhancePrompt() async throws(AgentError) -> String {
    await generation.enhancePrompt(in: connection)
    return generation.prompt
  }

  func promptFromImage() async throws(AgentError) -> String {
    await generation.promptFromImage(in: connection)
    return generation.prompt
  }

  // MARK: Following a job

  /// Reports the progress of what was just started until the app is idle again (a poll: the run, a pipeline and the
  /// queue each have their own state, and none of them calls back).
  private func watch(total: Int, since baseline: UUID?) {
    watcher?.cancel()
    let began = Date()
    watcher = Task { @MainActor [weak self] in
      var sawActivity = false
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard let self else { return }
        let made = self.resultIDs(since: baseline)
        let pass = self.generation.pipelinePass
        self.onJobEvent?(.progress(done: min(made.count, total), total: total, pass: pass?.index, passes: pass?.count))
        if self.isBusy { sawActivity = true; continue }
        guard sawActivity || Date().timeIntervalSince(began) > 3 else { continue }
        if case .failed(let error) = self.generation.session.phase {
          self.onJobEvent?(.failed("\(error)"))
        } else if self.generation.session.lastRunWasStopped {
          self.onJobEvent?(.stopped)
        } else {
          self.onJobEvent?(.finished(resultIDs: made))
        }
        return
      }
    }
  }

  private func resultIDs(since baseline: UUID?) -> [String] {
    var ids: [String] = []
    for result in generation.session.results {
      if result.id == baseline { break }
      ids.append(result.id.uuidString)
    }
    return ids.reversed()
  }

  // MARK: Pictures

  static func png(of image: CGImage, maxSide: Int) -> Data? {
    let longer = max(image.width, image.height)
    var output = image
    if longer > maxSide, maxSide > 0 {
      let scale = Double(maxSide) / Double(longer)
      let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
      guard
        let context = CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
          space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return nil }
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      guard let scaled = context.makeImage() else { return nil }
      output = scaled
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, output, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }
}
