import Foundation

/// What a plug-in handed over for a queue entry (`queue.capture`): a JSON object only the plug-in understands. The app keeps
/// it as it came and gives it back as it is (`queue.prepare`).
public struct QueueSnapshot: Codable, Equatable, Sendable {
  private indirect enum Value: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([Value])
    case object([String: Value])

    init?(any value: Any) {
      switch value {
      case is NSNull: self = .null
      case let number as NSNumber:
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
          self = .bool(number.boolValue)
        } else if CFNumberIsFloatType(number) {
          self = .number(number.doubleValue)
        } else {
          self = .integer(number.int64Value)
        }
      case let text as String: self = .string(text)
      case let list as [Any]:
        var items: [Value] = []
        for item in list {
          guard let converted = Value(any: item) else { return nil }
          items.append(converted)
        }
        self = .array(items)
      case let map as [String: Any]:
        var items: [String: Value] = [:]
        for (key, item) in map {
          guard let converted = Value(any: item) else { return nil }
          items[key] = converted
        }
        self = .object(items)
      default: return nil
      }
    }

    var any: Any {
      switch self {
      case .null: NSNull()
      case .bool(let flag): flag
      case .integer(let number): number
      case .number(let number): number
      case .string(let text): text
      case .array(let items): items.map(\.any)
      case .object(let items): items.mapValues(\.any)
      }
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if container.decodeNil() {
        self = .null
      } else if let flag = try? container.decode(Bool.self) {
        self = .bool(flag)
      } else if let number = try? container.decode(Int64.self) {
        self = .integer(number)
      } else if let number = try? container.decode(Double.self) {
        self = .number(number)
      } else if let text = try? container.decode(String.self) {
        self = .string(text)
      } else if let items = try? container.decode([Value].self) {
        self = .array(items)
      } else {
        self = .object(try container.decode([String: Value].self))
      }
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .null: try container.encodeNil()
      case .bool(let flag): try container.encode(flag)
      case .integer(let number): try container.encode(number)
      case .number(let number): try container.encode(number)
      case .string(let text): try container.encode(text)
      case .array(let items): try container.encode(items)
      case .object(let items): try container.encode(items)
      }
    }
  }

  private var items: [String: Value]

  /// nil when `jsonObject` is not a JSON object (a value that is not JSON, such as a date, is refused).
  public init?(jsonObject: Any) {
    guard let map = jsonObject as? [String: Any] else { return nil }
    var items: [String: Value] = [:]
    for (key, item) in map {
      guard let converted = Value(any: item) else { return nil }
      items[key] = converted
    }
    self.items = items
  }

  /// The object as a plug-in's message carries it.
  public var jsonObject: [String: Any] { items.mapValues(\.any) }

  public init(from decoder: any Decoder) throws {
    items = try decoder.singleValueContainer().decode([String: Value].self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(items)
  }
}
