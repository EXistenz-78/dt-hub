import Foundation

/// Messages between the app and a plug-in are JSON objects with a `type`; an unknown type gets
/// `{"type":"unsupported"}` and is not an error.
public enum PluginMessageType {
  public static let context = "context"
  public static let activate = "activate"
  public static let deactivate = "deactivate"
  /// App → plug-in: the project that is open and the folder for the plug-in's state in it (`PluginProject`).
  public static let project = "project"
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

/// App → plug-in: a project was opened. The plug-in keeps its state in `folder` (`state.json`) and loads what is there;
/// `adoptLegacy` is true once, for the first project ever, so a plug-in can move the state it had before projects into it.
public struct PluginProject: Codable, Equatable, Sendable {
  public var type = PluginMessageType.project
  public var name: String
  /// The plug-in's own folder inside the project; the app has created it.
  public var folder: String
  public var adoptLegacy: Bool

  public init(name: String, folder: String, adoptLegacy: Bool = false) {
    self.name = name
    self.folder = folder
    self.adoptLegacy = adoptLegacy
  }
}

/// A language model of the models folder, as a plug-in is told about it (`PluginContext.languageModels`).
public struct PluginLanguageModel: Codable, Equatable, Sendable {
  /// The name `llm`'s `model` asks for (the path below the models folder).
  public var name: String
  /// Its folder, to read files that come with the model.
  public var path: String
  /// True for a vision-language model: it can be given images.
  public var supportsImages: Bool
  /// The family the user assigned it to in Settings › LLM: "*" = all others, else the family key (Draw Things
  /// `version`); absent = none. Optional, an addition to contract 1.
  public var family: String?
  /// What it is for: "enhance", "describe", "both" or "plugins". Absent when the app does not say.
  public var use: String?

  public init(name: String, path: String, supportsImages: Bool, family: String? = nil, use: String? = nil) {
    self.name = name
    self.path = path
    self.supportsImages = supportsImages
    self.family = family
    self.use = use
  }
}

/// App → plug-in: where the app stands (sent when the plug-in is activated, when the model, its parameters or the
/// start image change, and when the user comes back to a tab).
public struct PluginContext: Codable, Equatable, Sendable {
  public var type = PluginMessageType.context
  public var model: String?
  public var family: String?
  public var parameters: GenerationParameters
  /// A folder the plug-in can exchange image files through.
  public var tempFolder: String
  /// The start image of the Control tab: the path of its file. Absent when there is none.
  public var startImage: String?
  /// The Moodboard pictures that are on, as files, in the order of the thumbnails. Absent when there are none.
  public var moodboard: [String]?
  /// The language models of the models folder. Absent when the app has none to list.
  public var languageModels: [PluginLanguageModel]?

  public init(
    model: String?, family: String?, parameters: GenerationParameters, tempFolder: String, startImage: String? = nil,
    moodboard: [String]? = nil, languageModels: [PluginLanguageModel]? = nil
  ) {
    self.model = model
    self.family = family
    self.parameters = parameters
    self.tempFolder = tempFolder
    self.startImage = startImage
    self.moodboard = moodboard
    self.languageModels = languageModels
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
