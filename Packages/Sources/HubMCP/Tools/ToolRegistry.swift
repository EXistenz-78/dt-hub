import Foundation
import MCP

public enum ToolLevel: Int, Sendable { case read, edit, control }

public enum ToolOutput: Equatable, Sendable {
  case text(String)
  case image(Data, mimeType: String)
}

public struct ToolResult: Equatable, Sendable {
  public var outputs: [ToolOutput]
  public var isError: Bool
  public static func failure(_ message: String) -> ToolResult { ToolResult(outputs: [.text(message)], isError: true) }
}

public struct ToolFailure: Error, Equatable, Sendable {
  public var message: String
  public init(_ message: String) { self.message = message }
}

/// One tool the server can offer. `handler` runs on the main actor with the arguments the client sent.
public struct ToolSpec: Sendable {
  public var name: String
  public var description: String
  public var inputSchema: Value
  public var level: ToolLevel
  /// Listed only while the current model's family has a specialist language model (spec §5).
  public var requiresSpecialist = false
  public var handler: @MainActor @Sendable (ToolContext, [String: Value]) async throws -> [ToolOutput]

  public init(
    name: String, description: String, schema: Value = ToolSpec.emptySchema, level: ToolLevel,
    requiresSpecialist: Bool = false,
    handler: @escaping @MainActor @Sendable (ToolContext, [String: Value]) async throws -> [ToolOutput]
  ) {
    self.name = name
    self.description = description
    self.inputSchema = schema
    self.level = level
    self.requiresSpecialist = requiresSpecialist
    self.handler = handler
  }

  public static let emptySchema: Value = .object(["type": .string("object"), "properties": .object([:])])

  /// An object schema: `properties` maps a name to (type, description); `required` lists the mandatory ones.
  public static func schema(_ properties: [(String, String, String)], required: [String] = []) -> Value {
    var props: [String: Value] = [:]
    for (name, type, text) in properties {
      props[name] = .object(["type": .string(type), "description": .string(text)])
    }
    var object: [String: Value] = ["type": .string("object"), "properties": .object(props)]
    if !required.isEmpty { object["required"] = .array(required.map { .string($0) }) }
    return .object(object)
  }

  public var tool: Tool {
    Tool(
      name: name, description: description, inputSchema: inputSchema,
      annotations: Tool.Annotations(readOnlyHint: level == .read, destructiveHint: false))
  }
}

/// What the tools share: the app, the settings and the policy objects.
@MainActor
public final class ToolContext {
  public let host: any AgentHost
  public let settings: @MainActor () -> RemoteControlSettings
  public let jobs: JobTracker
  public let ledger: BudgetLedger
  public let gate: ConsentGate
  public let paths: @MainActor () -> PathPolicy
  /// Queue entries this session added (an agent may remove only those).
  public var agentQueueEntries: Set<UUID> = []
  /// Called by tools that change what other tools depend on (the model): the registry re-checks the list.
  public var onHostChanged: (() -> Void)?

  public init(
    host: any AgentHost, settings: @escaping @MainActor () -> RemoteControlSettings, jobs: JobTracker,
    ledger: BudgetLedger, gate: ConsentGate, paths: @escaping @MainActor () -> PathPolicy
  ) {
    self.host = host
    self.settings = settings
    self.jobs = jobs
    self.ledger = ledger
    self.gate = gate
    self.paths = paths
  }
}

/// The tools visible in the current mode, and the dispatch of a call (spec §4, §6).
@MainActor
public final class ToolRegistry {
  public let context: ToolContext
  private let all: [ToolSpec]
  private var lastVisibleNames: [String] = []
  public var onListChanged: (() -> Void)?
  public let callLog = CallLog()

  public init(context: ToolContext, extraSpecs: [ToolSpec] = []) {
    self.context = context
    all = ReadTools.specs + EditTools.specs + ControlTools.specs + extraSpecs
    lastVisibleNames = visibleTools().map(\.name)
    context.onHostChanged = { [weak self] in self?.hostDidChange() }
  }

  public func visibleTools() -> [ToolSpec] {
    let mode = context.settings().mode
    return all.filter { isVisible($0, mode: mode) }
  }

  private func isVisible(_ spec: ToolSpec, mode: AccessMode) -> Bool {
    switch spec.level {
    case .read: break
    case .edit: if mode < .editFields { return false }
    case .control: if mode < .full { return false }
    }
    if spec.requiresSpecialist && !context.host.hasSpecialistLLM { return false }
    return true
  }

  /// Call when the mode, the model or the language-model assignments changed.
  public func hostDidChange() {
    let names = visibleTools().map(\.name)
    guard names != lastVisibleNames else { return }
    lastVisibleNames = names
    onListChanged?()
  }

  public func call(_ name: String, arguments: [String: Value]) async -> ToolResult {
    let result = await perform(name, arguments: arguments)
    var detail = ""
    if case .text(let text)? = result.outputs.first { detail = String(text.prefix(160)) }
    callLog.record(tool: name, isError: result.isError, detail: detail)
    return result
  }

  private func perform(_ name: String, arguments: [String: Value]) async -> ToolResult {
    let mode = context.settings().mode
    guard let spec = all.first(where: { $0.name == name }) else { return .failure("Unknown tool '\(name)'.") }
    guard isVisible(spec, mode: mode) else {
      return .failure(
        "Tool '\(name)' is not available now (mode: \(mode.rawValue)"
          + (spec.requiresSpecialist ? ", and the current model has no specialist language model" : "")
          + "). Ask the user to change it in DT Hub › Remote control.")
    }
    do {
      return ToolResult(outputs: try await spec.handler(context, arguments), isError: false)
    } catch let error as ToolFailure {
      return .failure(error.message)
    } catch let error as AgentError {
      return .failure(error.message)
    } catch {
      return .failure(error.localizedDescription)
    }
  }
}

// MARK: Argument helpers

extension Dictionary where Key == String, Value == MCP.Value {
  func string(_ key: String) -> String? {
    if case .string(let v)? = self[key] { return v }
    return nil
  }

  func requiredString(_ key: String) throws -> String {
    guard let v = string(key), !v.isEmpty else { throw ToolFailure("Missing argument '\(key)'.") }
    return v
  }

  func int(_ key: String) -> Int? {
    switch self[key] {
    case .int(let v)?: return v
    case .double(let v)?: return v == v.rounded() ? Int(v) : nil
    default: return nil
    }
  }

  func double(_ key: String) -> Double? {
    switch self[key] {
    case .double(let v)?: return v
    case .int(let v)?: return Double(v)
    default: return nil
    }
  }

  func bool(_ key: String) -> Bool? {
    if case .bool(let v)? = self[key] { return v }
    return nil
  }
}

func jsonText<T: Encodable>(_ value: T) -> ToolOutput {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  encoder.dateEncodingStrategy = .iso8601
  let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
  return .text(String(decoding: data, as: UTF8.self))
}
