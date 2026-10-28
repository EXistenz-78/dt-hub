import Foundation

/// Why a pipeline the plug-in guides ended.
public enum PluginSessionReason: String, Sendable {
  case finished, stopped, failed, closed
}

/// The picture the previous pass made, in a file in the session's folder.
public struct SessionPrevious: Equatable, Sendable {
  public var path: String
  public var width: Int
  public var height: Int

  public init(path: String, width: Int, height: Int) {
    self.path = path
    self.width = width
    self.height = height
  }
}

/// `session.next` (app → plug-in): which pass is wanted, of how many, and the result of the one before.
public struct SessionNextRequest: Equatable, Sendable {
  public var index: Int
  public var count: Int
  public var previous: SessionPrevious?

  public init(index: Int, count: Int, previous: SessionPrevious?) {
    self.index = index
    self.count = count
    self.previous = previous
  }

  public func data() -> Data {
    var object: [String: Any] = ["type": PluginMessageType.sessionNext, "index": index, "count": count]
    if let previous {
      object["previous"] = ["path": previous.path, "width": previous.width, "height": previous.height]
    }
    return (try? JSONSerialization.data(withJSONObject: object)) ?? PluginMessageType.bare(PluginMessageType.sessionNext)
  }
}

public enum PluginSession {
  /// `session.end` (app → plug-in), with the reason. `previous` is the result of the last pass when no later `session.next`
  /// carried it (the pipeline ran its declared passes to the end): without it the plug-in would never see the last result.
  public static func endMessage(_ reason: PluginSessionReason, previous: SessionPrevious? = nil) -> Data {
    var object: [String: Any] = ["type": PluginMessageType.sessionEnd, "reason": reason.rawValue]
    if let previous {
      object["previous"] = ["path": previous.path, "width": previous.width, "height": previous.height]
    }
    return (try? JSONSerialization.data(withJSONObject: object)) ?? PluginMessageType.bare(PluginMessageType.sessionEnd)
  }
}

/// What a plug-in answers to `session.next`: a pass, or "done".
public enum SessionAnswer: Equatable, Sendable {
  case pass(PipelineStep)
  case done
  case invalid(String)

  /// A pass needs a size that is a multiple of 64 and at most `tileLimit` on each side. The start image is optional (no start image: an empty canvas),
  /// but a mask needs one.
  public static func parse(_ data: Data?, tileLimit: Int) -> SessionAnswer {
    guard let data, let root = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let object) = root
    else { return .invalid("no answer") }
    if case .bool(true)? = object["done"] { return .done }
    var step = PipelineStep(object)
    // The strength is read from a guided pass only: a static pass of a plug-in never sets it (see `PipelineStep`).
    step.strength = PluginContribution.strength(object["strength"])
    guard let size = step.size else { return .invalid("the pass has no size") }
    // Without a start image the pass draws on an empty canvas of its size; a mask belongs to the picture it covers.
    guard step.startImage != nil || step.mask == nil else { return .invalid("a mask needs a startImage") }
    guard size.width > 0, size.height > 0, size.width % 64 == 0, size.height % 64 == 0 else {
      return .invalid("size must be a multiple of 64")
    }
    guard max(size.width, size.height) <= tileLimit else { return .invalid("size is larger than \(tileLimit)") }
    return .pass(step)
  }
}
