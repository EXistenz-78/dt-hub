import Foundation

@testable import HubMCP

/// A stand-in for the app: records what the tools ask and answers with fixed data.
@MainActor
final class FakeAgentHost: AgentHost {
  var stateValue = AgentState()
  var modelList = [AgentModel(file: "flux2.ckpt", name: "FLUX.2 klein", family: "flux2", kind: "image")]
  var loraList: [AgentLoRA] = []
  var guides: [String: String] = ["flux2": "Write long natural prompts."]
  var currentFamily: String? = "flux2"
  var hasSpecialistLLM = false
  var resultList: [AgentResult] = []
  var images: [String: Data] = [:]
  var queue: [AgentQueueEntry] = []
  var pluginList: [AgentPlugin] = []
  var onJobEvent: ((AgentJobEvent) -> Void)?

  // Recorded calls
  var calls: [String] = []
  var appliedFields: [[String: AgentValue]] = []
  var moodboards: [(items: [AgentImage], replace: Bool)] = []
  var startImages: [AgentImage] = []
  var plan = AgentRunPlan(images: 1, summary: "1 image")
  var startError: AgentError?
  var setModelError: AgentError?
  var knownLoRAs: Set<String> = []
  var replacedCount = 0
  var unappliedKeys: Set<String> = []
  var queueRunning = false
  var advanced: [String: AgentValue] = ["clipSkip": .int(1), "tiledDecoding": .bool(false), "refinerModel": .string("")]
  var advancedShown = ["clipSkip", "tiledDecoding"]
  var projectList = [AgentProject(name: "Test vari", isCurrent: true), AgentProject(name: "Altro", isCurrent: false)]
  var server = AgentServerStatus(mode: "managed", connected: true, detail: "connected", otherMode: "attach", canSwitch: true, cannotSwitchReason: nil)
  var moodboardToClear = 0
  var hasStart = true
  var presetList = ["Portrait"]

  func state() -> AgentState { stateValue }
  func models() -> [AgentModel] { modelList }
  func loras() -> [AgentLoRA] { loraList }
  func presetNames() -> [String] { presetList }
  func pipelineNames() -> [String] { ["Upscale chain"] }
  func promptGuide(family: String) -> String? { guides[family] }
  func results() -> [AgentResult] { resultList }
  func resultImage(id: String, maxSide: Int) -> Data? { images[id] }
  func queueEntries() -> [AgentQueueEntry] { queue }
  func plugins() -> [AgentPlugin] { pluginList }

  var pluginToolList: [AgentPluginTool] = []
  var pluginToolCalls: [(plugin: String, tool: String, arguments: Data)] = []
  var pluginToolAnswer = "answer"
  func pluginTools() -> [AgentPluginTool] { pluginToolList }
  var pluginToolStartsRun = false
  var pluginPipelinePlan: AgentRunPlan?
  func callPluginTool(pluginID: String, tool: String, arguments: Data) async throws(AgentError) -> AgentPluginAnswer {
    pluginToolCalls.append((pluginID, tool, arguments))
    return AgentPluginAnswer(text: pluginToolAnswer, startsRun: pluginToolStartsRun)
  }
  func planPluginPipeline(pluginID: String) throws(AgentError) -> AgentRunPlan {
    guard let pluginPipelinePlan else { throw .invalid("No guided pipeline of this plug-in is ready.") }
    return pluginPipelinePlan
  }
  func startPluginPipeline(pluginID: String) throws(AgentError) {
    if let startError { throw startError }
    calls.append("startPluginPipeline \(pluginID)")
  }

  func setFields(_ fields: [String: AgentValue]) throws(AgentError) -> [String] {
    appliedFields.append(fields)
    return fields.keys.filter { !unappliedKeys.contains($0) }.sorted()
  }
  func addLoRA(file: String, weight: Double) throws(AgentError) {
    guard knownLoRAs.contains(file) else { throw .invalid("Unknown LoRA '\(file)'.") }
    calls.append("addLoRA \(file) \(weight)")
  }
  func setLoRAWeight(file: String, weight: Double) throws(AgentError) { calls.append("setLoRAWeight \(file) \(weight)") }
  func removeLoRA(file: String) throws(AgentError) { calls.append("removeLoRA \(file)") }
  func setMoodboard(_ items: [AgentImage], replace: Bool) async throws(AgentError) -> Int {
    moodboards.append((items, replace))
    return replacedCount
  }
  func setStartImage(_ image: AgentImage) async throws(AgentError) { startImages.append(image) }
  func clearMoodboard() throws(AgentError) -> Int {
    calls.append("clearMoodboard")
    return moodboardToClear
  }
  func clearStartImage() throws(AgentError) {
    guard hasStart else { throw .invalid("There is no start image.") }
    calls.append("clearStartImage")
  }
  func serverStatus() -> AgentServerStatus { server }
  func switchServer() async throws(AgentError) -> AgentServerStatus {
    guard server.canSwitch else { throw .unavailable(server.cannotSwitchReason ?? "cannot switch") }
    calls.append("switchServer")
    server = AgentServerStatus(mode: server.otherMode, connected: true, detail: "connected", otherMode: server.mode, canSwitch: true, cannotSwitchReason: nil)
    return server
  }
  func advancedValues() -> [String: AgentValue] { advanced }
  func advancedApplicable() -> [String] { advancedShown }
  func setAdvanced(_ values: [String: AgentValue]) throws(AgentError) -> [String] {
    for key in values.keys where advanced[key] == nil { throw .invalid("Unknown advanced field '\(key)'.") }
    calls.append("setAdvanced \(values.keys.sorted().joined(separator: ","))")
    return values.keys.sorted()
  }
  func setIncremental(_ on: Bool) { calls.append("setIncremental \(on)") }
  func projects() -> [AgentProject] { projectList }
  func openProject(name: String) async throws(AgentError) {
    guard projectList.contains(where: { $0.name == name }) else { throw .invalid("No project named '\(name)'.") }
    calls.append("openProject \(name)")
  }
  func createProject(name: String) async throws(AgentError) { calls.append("createProject \(name)") }
  func clearPipeline() throws(AgentError) { calls.append("clearPipeline") }
  var pipelineList: [String] = ["Hero"]
  func selectPipeline(named name: String) throws(AgentError) {
    guard pipelineList.contains(name) else { throw .invalid("Unknown pipeline '\(name)'.") }
    calls.append("selectPipeline \(name)")
  }
  func recallResult(id: String, prompt: Bool, parameters: Bool) throws(AgentError) {
    calls.append("recallResult \(id) \(prompt) \(parameters)")
  }
  func setStrength(_ value: Double) throws(AgentError) { calls.append("setStrength \(value)") }
  func loadPreset(named: String) -> String? { calls.append("loadPreset \(named)"); return nil }
  func savePreset(named: String) throws(AgentError) { calls.append("savePreset \(named)") }

  func setModel(file: String) throws(AgentError) {
    if let setModelError { throw setModelError }
    calls.append("setModel \(file)")
  }
  func planRun() -> AgentRunPlan { plan }
  func planPipeline(named: String) throws(AgentError) -> AgentRunPlan { plan }
  func planQueue() -> AgentRunPlan { plan }
  func startRun() throws(AgentError) {
    if let startError { throw startError }
    calls.append("startRun")
  }
  func startPipeline(named: String) throws(AgentError) {
    if let startError { throw startError }
    calls.append("startPipeline \(named)")
  }
  func startQueue() throws(AgentError) {
    if let startError { throw startError }
    calls.append("startQueue")
  }
  func stop() { calls.append("stop") }
  func stopQueue() { calls.append("stopQueue") }
  func definePipeline(steps: [AgentPipelineStep]) throws(AgentError) -> String {
    calls.append("definePipeline \(steps.count)")
    return "Agent pipeline"
  }
  func queueAdd() async throws(AgentError) -> UUID {
    if queueRunning { throw .busy(jobID: nil) }
    let id = UUID()
    queue.append(AgentQueueEntry(id: id, summary: "entry", status: "pending"))
    return id
  }
  func queueRemove(id: UUID) throws(AgentError) { queue.removeAll { $0.id == id } }
  func enhancePrompt() async throws(AgentError) -> String { "enhanced" }
  func promptFromImage() async throws(AgentError) -> String { "described" }
}

/// Always answers the same to a confirmation, and remembers the questions.
@MainActor
final class StubPrompter: ConsentPrompter {
  var answer = true
  private(set) var asked: [String] = []
  var onAsk: (() -> Void)?
  func ask(_ summary: String, timeoutSeconds: Int) async -> Bool {
    asked.append(summary)
    onAsk?()
    return answer
  }
}

/// Everything a registry test needs, wired together.
@MainActor
struct Harness {
  let host = FakeAgentHost()
  let jobs = JobTracker()
  let prompter = StubPrompter()
  let ledger: BudgetLedger
  let registry: ToolRegistry
  let context: ToolContext
  var settings: Box

  @MainActor final class Box { var value = RemoteControlSettings() }

  init(mode: AccessMode = .readOnly, extraSpecs: [ToolSpec] = [], roots: [URL] = []) {
    let box = Box()
    box.value.mode = mode
    settings = box
    ledger = BudgetLedger(settings: { box.value })
    let gate = ConsentGate(ledger: ledger, settings: { box.value }, prompter: prompter)
    context = ToolContext(
      host: host, settings: { box.value }, jobs: jobs, ledger: ledger, gate: gate, paths: { PathPolicy(roots: roots) })
    registry = ToolRegistry(context: context, extraSpecs: extraSpecs)
  }
}
