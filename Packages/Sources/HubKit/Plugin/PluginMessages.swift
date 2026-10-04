import Foundation

/// Messages between the app and a plug-in are JSON objects with a `type`; an unknown type gets
/// `{"type":"unsupported"}` and is not an error.
public enum PluginMessageType {
  public static let context = "context"
  public static let activate = "activate"
  public static let deactivate = "deactivate"
  public static let notice = "notice"
  /// Plug-in → app: values, LoRAs, pictures, a pipeline (`PluginContribution`).
  public static let contribute = "contribute"
  /// Plug-in → app: presets to add to the Preset menu (`PluginPresets`).
  public static let presets = "presets"
  /// Plug-in → app: a question for the language model; the answer is `{"type":"llm","text":…}`.
  public static let llm = "llm"
  /// The answer to a message the app could not use: `{"type":"error","text":…}`.
  public static let error = "error"
  public static let unsupported = "unsupported"
  public static let ok = "ok"

  /// The `type` of a JSON message, if it is one.
  public static func of(_ data: Data) -> String? {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String
  }

  /// `{"type":"error","text":text}` as data.
  public static func failure(_ text: String) -> Data {
    (try? JSONSerialization.data(withJSONObject: ["type": error, "text": text])) ?? bare(error)
  }

  /// `{"type": type}` as data.
  public static func bare(_ type: String) -> Data {
    Data(#"{"type":"\#(type)"}"#.utf8)
  }
}

/// App → plug-in: where the app stands (sent when the plug-in is activated and when the model changes).
public struct PluginContext: Codable, Equatable, Sendable {
  public var type = PluginMessageType.context
  public var model: String?
  public var family: String?
  public var parameters: GenerationParameters
  /// A folder the plug-in can exchange image files through.
  public var tempFolder: String

  public init(model: String?, family: String?, parameters: GenerationParameters, tempFolder: String) {
    self.model = model
    self.family = family
    self.parameters = parameters
    self.tempFolder = tempFolder
  }
}

/// Plug-in → app: a line to show to the user.
public struct PluginNotice: Codable, Equatable, Sendable {
  public var type = PluginMessageType.notice
  public var text: String
  public var isError: Bool

  public init(text: String, isError: Bool = false) {
    self.text = text
    self.isError = isError
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    text = try container.decode(String.self, forKey: .text)
    isError = (try? container.decodeIfPresent(Bool.self, forKey: .isError)) ?? false
  }
}
