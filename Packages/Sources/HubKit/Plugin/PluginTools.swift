import Foundation

/// How much a tool of a plug-in may do. `read` only looks; `edit` changes the Generation tab or the plug-in's own data;
/// `generate` is reserved for tools that make the app generate (they go through the app's Run path, which applies the
/// budget and the confirmation threshold whatever level is declared).
public enum PluginToolLevel: String, Codable, Equatable, Sendable {
  case read, edit, generate
}

/// One argument of a plug-in tool. The schema stays this small on purpose: flat arguments, no nesting.
public struct PluginToolParameter: Codable, Equatable, Sendable {
  public static let types: Set<String> = ["string", "number", "integer", "boolean"]

  public var name: String
  /// "string", "number", "integer" or "boolean".
  public var type: String
  public var description: String
  public var required: Bool
  /// The only values a string may take.
  public var values: [String]?
  /// "image": the string names a picture (a `result_id` of the agent's session or an allowed path); the app checks it and
  /// hands the plug-in the absolute path of the file. Nil for plain text.
  public var format: String?

  public static let imageFormat = "image"

  public init(
    name: String, type: String = "string", description: String, required: Bool = false, values: [String]? = nil,
    format: String? = nil
  ) {
    self.name = name
    self.type = type
    self.description = description
    self.required = required
    self.values = values
    self.format = format
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "string"
    description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? ""
    required = (try? container.decodeIfPresent(Bool.self, forKey: .required)) ?? false
    values = (try? container.decodeIfPresent([String].self, forKey: .values)) ?? nil
    format = (try? container.decodeIfPresent(String.self, forKey: .format)) ?? nil
    guard Self.types.contains(type), PluginToolDeclaration.isValidName(name) else {
      throw DecodingError.dataCorruptedError(forKey: .name, in: container, debugDescription: "bad parameter")
    }
  }

  private enum CodingKeys: String, CodingKey { case name, type, description, required, values, format }
}

/// A tool a plug-in offers to agents (an optional `tools` list in the manifest; an addition to contract 1). The app calls it
/// with a `tool.call` message and the plug-in answers `tool.result`.
public struct PluginToolDeclaration: Codable, Equatable, Sendable {
  /// Lowercase letters, digits and underscores, starting with a letter, 40 characters at most.
  public var name: String
  public var description: String
  public var level: PluginToolLevel
  public var parameters: [PluginToolParameter]
  /// Model families the tool makes sense for; nil or empty = those of the plug-in.
  public var families: [String]?
  /// How long the app waits for the answer, in seconds (default 60, at most 600).
  public var timeout: Double?

  public static let defaultTimeout = 60.0
  public static let maxTimeout = 600.0

  public init(
    name: String, description: String, level: PluginToolLevel = .read, parameters: [PluginToolParameter] = [],
    families: [String]? = nil, timeout: Double? = nil
  ) {
    self.name = name
    self.description = description
    self.level = level
    self.parameters = parameters
    self.families = families
    self.timeout = timeout
  }

  /// A declaration that cannot be read, or has a bad name, is left out of the manifest without costing the plug-in.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    guard Self.isValidName(name) else {
      throw DecodingError.dataCorruptedError(forKey: .name, in: container, debugDescription: "bad tool name")
    }
    description = try container.decode(String.self, forKey: .description)
    level = try container.decode(PluginToolLevel.self, forKey: .level)
    parameters = ((try? container.decodeIfPresent([Lenient<PluginToolParameter>].self, forKey: .parameters)) ?? nil)?
      .compactMap(\.value) ?? []
    families = (try? container.decodeIfPresent([String].self, forKey: .families)) ?? nil
    timeout = (try? container.decodeIfPresent(Double.self, forKey: .timeout)) ?? nil
  }

  public static func isValidName(_ name: String) -> Bool {
    guard let first = name.unicodeScalars.first, name.count <= 40, ("a"..."z").contains(first) else { return false }
    return name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
  }

  public var effectiveTimeout: Duration {
    .seconds(min(max(timeout ?? Self.defaultTimeout, 1), Self.maxTimeout))
  }

  /// Whether the tool applies to a model family (nil = unknown family: it does).
  public func supports(family: String?) -> Bool {
    guard let family, let families, !families.isEmpty else { return true }
    return families.contains(family)
  }

  private enum CodingKeys: String, CodingKey { case name, description, level, parameters, families, timeout }
}

/// An element of a list that may fail to decode without costing the rest of the list.
struct Lenient<Value: Decodable>: Decodable {
  let value: Value?
  init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
}

/// App → plug-in: `tool.call`. An agent asks for a tool the manifest declared; `arguments` is a flat JSON object.
public struct PluginToolCall: Codable, Equatable, Sendable {
  public var type = PluginMessageType.toolCall
  public var tool: String
  /// The arguments as a JSON object, already checked against the declaration.
  public var arguments: Data

  public init(tool: String, arguments: Data) {
    self.tool = tool
    self.arguments = arguments
  }

  /// The message as bytes: `{"type":"tool.call","tool":…,"arguments":{…}}`.
  public func message() -> Data {
    let object = (try? JSONSerialization.jsonObject(with: arguments)) ?? [String: Any]()
    let body: [String: Any] = ["type": type, "tool": tool, "arguments": object]
    return (try? JSONSerialization.data(withJSONObject: body)) ?? PluginMessageType.bare(type)
  }
}

/// What a plug-in answered to `tool.call`: `{"type":"tool.result","text":…}` (add `"isError":true` for a failure the agent
/// should see), or the usual `error` / `unsupported`.
public enum PluginToolOutcome: Equatable, Sendable {
  case text(String)
  /// The text, and the plug-in asks the app to run the guided pipeline it has just proposed (`"startsRun": true`).
  case startsRun(String)
  case failure(String)

  /// The longest answer taken, in characters.
  public static let maxLength = 40_000

  public static func parse(_ answer: Data?) -> PluginToolOutcome {
    guard let answer, let object = (try? JSONSerialization.jsonObject(with: answer)) as? [String: Any],
      let type = object["type"] as? String
    else { return .failure("The plug-in did not answer in time.") }
    switch type {
    case PluginMessageType.toolResult:
      let text = String((object["text"] as? String ?? "").prefix(maxLength))
      if (object["isError"] as? Bool) == true { return .failure(text) }
      return (object["startsRun"] as? Bool) == true ? .startsRun(text) : .text(text)
    case PluginMessageType.error:
      return .failure(object["text"] as? String ?? "The plug-in could not do it.")
    case PluginMessageType.unsupported:
      return .failure("This version of the plug-in does not handle the tool.")
    default:
      return .failure("The plug-in answered something unexpected.")
    }
  }
}

extension PluginManifest {
  /// The declared tool with this name.
  public func tool(named name: String) -> PluginToolDeclaration? { tools?.first { $0.name == name } }
}
