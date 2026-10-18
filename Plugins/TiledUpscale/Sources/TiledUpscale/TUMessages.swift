import Foundation

/// `session.next` as the app sends it: which pass is wanted, of how many, and the result of the one before.
struct TUNextRequest: Equatable, Sendable {
  struct Previous: Equatable, Sendable {
    let path: String
    let width: Int
    let height: Int
  }

  let index: Int
  let count: Int
  let previous: Previous?
}

enum TUMessages {
  /// The request from the app's JSON; nil when the message is not `session.next` or lacks its numbers.
  static func parseNext(_ data: Data) -> TUNextRequest? {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      object["type"] as? String == "session.next", let index = object["index"] as? Int,
      let count = object["count"] as? Int
    else { return nil }
    var previous: TUNextRequest.Previous?
    if let box = object["previous"] as? [String: Any], let path = box["path"] as? String,
      let width = box["width"] as? Int, let height = box["height"] as? Int
    {
      previous = TUNextRequest.Previous(path: path, width: width, height: height)
    }
    return TUNextRequest(index: index, count: count, previous: previous)
  }

  static let done = Data(#"{"done":true}"#.utf8)
}
