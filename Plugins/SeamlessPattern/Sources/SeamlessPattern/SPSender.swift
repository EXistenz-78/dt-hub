import Foundation

/// How the tiling is asked for: both directions, only left-right, only up-down (the values of the `seamless` key).
enum SPMode: String, Codable, CaseIterable, Sendable {
  case both, leftRight, upDown

  var judgesLeftRight: Bool { self != .upDown }
  var judgesUpDown: Bool { self != .leftRight }
}

/// The JSON of `contribute`: a one-step pipeline "Seamless" whose step only carries the flag, so prompt, seed, size,
/// LoRAs and preset stay the user's. `stop` takes it back (`"pipeline": null` withdraws only this plug-in's own).
enum SPSender {
  static func prepare(mode: SPMode) -> Data {
    encode([
      "type": "contribute",
      "pipeline": ["name": "Seamless", "steps": [["title": "Seamless", "seamless": mode.rawValue]]],
    ])
  }

  static func stop() -> Data {
    encode(["type": "contribute", "pipeline": NSNull()])
  }

  /// The message as `DTHubHost.contribute` wants it: without the `type`, which the host adds.
  static func body(_ message: Data) -> [String: Any]? {
    guard var object = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any] else { return nil }
    object["type"] = nil
    return object
  }

  private static func encode(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
  }
}
