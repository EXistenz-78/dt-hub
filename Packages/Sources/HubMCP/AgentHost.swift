import Foundation

/// A value an agent sets in a field of the Generation tab.
public enum AgentValue: Codable, Equatable, Sendable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)

  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let v = try? c.decode(Bool.self) { self = .bool(v) }
    else if let v = try? c.decode(Int.self) { self = .int(v) }
    else if let v = try? c.decode(Double.self) { self = .double(v) }
    else { self = .string(try c.decode(String.self)) }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let v): try c.encode(v)
    case .int(let v): try c.encode(v)
    case .double(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    }
  }
}

/// A picture an agent hands to the app: a result of this session, or a file in an allowed folder.
public struct AgentImage: Equatable, Sendable {
  public enum Source: Equatable, Sendable {
    case result(id: String)
    case path(String)
  }
  public var source: Source
  public var weight: Double?

  public init(_ source: Source, weight: Double? = nil) {
    self.source = source
    self.weight = weight
  }
}

public struct AgentError: Error, Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    /// A run (or another job) is already going on; `jobID` is nil when the user started it by hand.
    case busy(jobID: String?)
    case invalid
    case unavailable
  }
  public var kind: Kind
  public var message: String

  public init(_ kind: Kind, _ message: String) {
    self.kind = kind
    self.message = message
  }

  public static func invalid(_ message: String) -> AgentError { AgentError(.invalid, message) }
  public static func unavailable(_ message: String) -> AgentError { AgentError(.unavailable, message) }
  public static func busy(jobID: String?) -> AgentError {
    AgentError(.busy(jobID: jobID), jobID.map { "A job is already running (job_id \($0))." } ?? "A generation is already running.")
  }
}

public struct AgentModel: Equatable, Sendable, Codable {
  public var file: String
  public var name: String
  public var family: String
  public var kind: String
  public init(file: String, name: String, family: String, kind: String) {
    self.file = file
    self.name = name
    self.family = family
    self.kind = kind
  }
}

public struct AgentLoRA: Equatable, Sendable, Codable {
  public var file: String
  public var name: String
  public var families: [String]
  public init(file: String, name: String, families: [String]) {
    self.file = file
    self.name = name
    self.families = families
  }
}

public struct AgentLoRAUse: Equatable, Sendable, Codable {
  public var file: String
  public var weight: Double
  public init(file: String, weight: Double) {
    self.file = file
    self.weight = weight
  }
}

public struct AgentResult: Equatable, Sendable, Codable {
  public var id: String
  public var path: String
  public var prompt: String
  public var model: String
  public var date: Date
  public init(id: String, path: String, prompt: String, model: String, date: Date) {
    self.id = id
    self.path = path
    self.prompt = prompt
    self.model = model
    self.date = date
  }
}

public struct AgentQueueEntry: Equatable, Sendable, Codable {
  public var id: UUID
  public var summary: String
  public var status: String
  public init(id: UUID, summary: String, status: String) {
    self.id = id
    self.summary = summary
    self.status = status
  }
}

public struct AgentPlugin: Equatable, Sendable, Codable {
  public var id: String
  public var name: String
  public var isActive: Bool
  /// Why the plug-in does not work with the current model, when it does not.
  public var unavailableReason: String?
  public init(id: String, name: String, isActive: Bool, unavailableReason: String? = nil) {
    self.id = id
    self.name = name
    self.isActive = isActive
    self.unavailableReason = unavailableReason
  }
}

/// Which image server DT Hub talks to: "managed" is the one DT Hub starts itself (the CLI server), "attach" is the
/// server of the Draw Things app.
public struct AgentServerStatus: Equatable, Sendable, Codable {
  public var mode: String
  public var connected: Bool
  public var detail: String
  public var otherMode: String
  public var canSwitch: Bool
  public var cannotSwitchReason: String?
  public init(mode: String, connected: Bool, detail: String, otherMode: String, canSwitch: Bool, cannotSwitchReason: String?) {
    self.mode = mode
    self.connected = connected
    self.detail = detail
    self.otherMode = otherMode
    self.canSwitch = canSwitch
    self.cannotSwitchReason = cannotSwitchReason
  }
}

/// The Generation tab as an agent sees it.
public struct AgentState: Equatable, Sendable, Codable {
  public var modelFile: String?
  public var modelName: String?
  public var family: String?
  public var prompt = ""
  public var negativePrompt = ""
  public var fields: [String: AgentValue] = [:]
  public var loras: [AgentLoRAUse] = []
  public var moodboardCount = 0
  public var hasStartImage = false
  public var strength: Double?
  public var isGenerating = false
  /// A pipeline selected in the app: a plain run would run it.
  public var selectedPipeline: String?
  public init() {}
}

/// What a run (or a pipeline, or the queue) is going to cost, asked before it starts.
public struct AgentRunPlan: Equatable, Sendable {
  public var images: Int
  public var estimatedCU: Int?
  /// Names the model and the count for the confirmation box ("12 images with FLUX.2 klein").
  public var summary: String
  public init(images: Int, estimatedCU: Int? = nil, summary: String = "") {
    self.images = images
    self.estimatedCU = estimatedCU
    self.summary = summary
  }
}

public struct AgentPipelineStep: Equatable, Sendable {
  public var prompt: String?
  public var negativePrompt: String?
  public var fields: [String: AgentValue]
  public init(prompt: String? = nil, negativePrompt: String? = nil, fields: [String: AgentValue] = [:]) {
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.fields = fields
  }
}

/// Progress of the one job the app can run at a time.
public enum AgentJobEvent: Equatable, Sendable {
  case progress(done: Int, total: Int, pass: Int?, passes: Int?)
  case finished(resultIDs: [String])
  case failed(String)
  case stopped
}

/// What the MCP server needs from the app. The app implements it on the Generation tab, the queue, the
/// contributions and the results; tests implement it with a fake (spec 2026-11-08 §3).
@MainActor
public protocol AgentHost: AnyObject {
  // Reading
  func state() -> AgentState
  func models() -> [AgentModel]
  func loras() -> [AgentLoRA]
  func presetNames() -> [String]
  func pipelineNames() -> [String]
  func promptGuide(family: String) -> String?
  var currentFamily: String? { get }
  /// True when the current model's family has a specialist language model (not an "all others" one).
  var hasSpecialistLLM: Bool { get }
  func results() -> [AgentResult]
  /// PNG data of the result scaled so its longer side is at most `maxSide`.
  func resultImage(id: String, maxSide: Int) -> Data?
  func queueEntries() -> [AgentQueueEntry]
  func plugins() -> [AgentPlugin]
  func serverStatus() -> AgentServerStatus

  // Editing the tab
  func setFields(_ fields: [String: AgentValue]) throws(AgentError) -> [String]
  func addLoRA(file: String, weight: Double) throws(AgentError)
  func setLoRAWeight(file: String, weight: Double) throws(AgentError)
  func removeLoRA(file: String) throws(AgentError)
  /// Returns how many pictures were replaced.
  func setMoodboard(_ items: [AgentImage], replace: Bool) async throws(AgentError) -> Int
  func setStartImage(_ image: AgentImage) async throws(AgentError)
  /// Returns how many pictures were taken off.
  func clearMoodboard() throws(AgentError) -> Int
  func clearStartImage() throws(AgentError)
  /// Deselects the pipeline a plain run would execute.
  func clearPipeline() throws(AgentError)
  func setStrength(_ value: Double) throws(AgentError)
  func loadPreset(named: String) -> String?
  func savePreset(named: String) throws(AgentError)

  // Controlling
  func setModel(file: String) throws(AgentError)
  /// Switches between the two image servers and waits (up to a minute) until the new one answers.
  func switchServer() async throws(AgentError) -> AgentServerStatus
  func planRun() -> AgentRunPlan
  func planPipeline(named: String) throws(AgentError) -> AgentRunPlan
  func planQueue() -> AgentRunPlan
  func startRun() throws(AgentError)
  func startPipeline(named: String) throws(AgentError)
  func startQueue() throws(AgentError)
  func stop()
  func stopQueue()
  func definePipeline(steps: [AgentPipelineStep]) throws(AgentError) -> String
  func queueAdd() async throws(AgentError) -> UUID
  func queueRemove(id: UUID) throws(AgentError)
  func enhancePrompt() async throws(AgentError) -> String
  func promptFromImage() async throws(AgentError) -> String

  /// Set by the server; the app calls it as the job moves.
  var onJobEvent: ((AgentJobEvent) -> Void)? { get set }
}
