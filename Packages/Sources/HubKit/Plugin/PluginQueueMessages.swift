import Foundation

/// Why a plug-in could not take part in the queue.
public enum PluginQueueProblem: Error, Equatable, Sendable {
  /// The plug-in is not loaded, or did not answer.
  case notLoaded
  /// The plug-in does not know the message.
  case unsupported
  /// The plug-in answered with an error (its own words, possibly empty).
  case refused(String)
}

/// The messages of the queue for a plug-in that guides a pipeline (queue design for guided pipelines §4).
public enum PluginQueue {
  /// `queue.capture`: the plug-in writes its files into `folder` and answers `{"type":"ok","state":{…}}`.
  public static func captureRequest(folder: URL) -> Data {
    encode(["type": PluginMessageType.queueCapture, "folder": folder.path])
  }

  /// `queue.prepare`: the plug-in rebuilds its session from `folder` and `state`. `model` and `family` are the header's
  /// after the entry's model was chosen: a plug-in that is not active has not been told.
  public static func prepareRequest(folder: URL, state: QueueSnapshot, model: String, family: String?) -> Data {
    var message: [String: Any] = [
      "type": PluginMessageType.queuePrepare, "folder": folder.path, "state": state.jsonObject, "model": model,
    ]
    if let family { message["family"] = family }
    return encode(message)
  }

  /// The plug-in's answer to `queue.capture`.
  public static func parseCapture(_ answer: Data?) -> Result<QueueSnapshot, PluginQueueProblem> {
    guard let answer else { return .failure(.notLoaded) }
    let object = (try? JSONSerialization.jsonObject(with: answer)) as? [String: Any]
    switch object?["type"] as? String {
    case PluginMessageType.unsupported: return .failure(.unsupported)
    case PluginMessageType.error: return .failure(.refused(object?["text"] as? String ?? ""))
    case PluginMessageType.ok:
      if let state = object?["state"], let snapshot = QueueSnapshot(jsonObject: state) { return .success(snapshot) }
      return .failure(.refused(""))
    default: return .failure(.refused(""))
    }
  }

  /// The plug-in's answer to `queue.prepare`: nil when it is ready, otherwise why not.
  public static func parsePrepare(_ answer: Data?) -> PluginQueueProblem? {
    guard let answer else { return .notLoaded }
    let object = (try? JSONSerialization.jsonObject(with: answer)) as? [String: Any]
    switch object?["type"] as? String {
    case PluginMessageType.ok: return nil
    case PluginMessageType.unsupported: return .unsupported
    case PluginMessageType.error: return .refused(object?["text"] as? String ?? "")
    default: return .refused("")
    }
  }

  private static func encode(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
  }
}
