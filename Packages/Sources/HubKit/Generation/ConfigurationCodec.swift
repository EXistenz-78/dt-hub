/// The model and parameters of a generation: what the Draw Things configuration JSON holds.
public struct ConfigurationState: Equatable, Sendable {
  public var model: String
  public var parameters: GenerationParameters

  public init(model: String, parameters: GenerationParameters) {
    self.model = model
    self.parameters = parameters
  }
}

/// Why a JSON text could not be applied; the message is the library's, for display.
public struct ConfigurationError: Error, Equatable, Sendable {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }
}

/// Translates between the Draw Things configuration JSON (the "Copy Configuration" format,
/// 97 fields) and DT Hub's parameters (spec §6, level 3). DTBridge implements it; the
/// settings DT Hub has no card for are kept in `GenerationParameters.extra`.
public protocol ConfigurationCodec: Sendable {
  /// The complete configuration as pretty-printed JSON, sorted keys; a random seed is -1.
  func exportJSON(_ state: ConfigurationState) -> String
  /// nil when applying the text to `state` would work: a valid complete or partial
  /// configuration whose values are in range. Else what is wrong.
  func validate(_ json: String, for state: ConfigurationState) -> String?
  /// The top-level keys of `json` that are not Draw Things settings (typos, newer versions):
  /// applying the text ignores them.
  func unknownKeys(in json: String) -> [String]
  /// Applies the keys present in `json` on top of `state`: the others stay as they are.
  func apply(json: String, to state: ConfigurationState) throws(ConfigurationError) -> ConfigurationState
}
