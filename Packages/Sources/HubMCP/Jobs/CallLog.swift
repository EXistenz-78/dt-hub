import Foundation
import Observation

public struct CallLogEntry: Identifiable, Equatable, Sendable {
  public let id = UUID()
  public let date = Date()
  public let tool: String
  public let isError: Bool
  public let detail: String
}

/// The last calls an agent made (spec §6: "registro delle chiamate"), shown in the Remote control panel.
@MainActor
@Observable
public final class CallLog {
  public static let limit = 200
  public private(set) var entries: [CallLogEntry] = []

  public init() {}

  public func record(tool: String, isError: Bool, detail: String) {
    entries.append(CallLogEntry(tool: tool, isError: isError, detail: detail))
    if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
  }

  public func clear() { entries.removeAll() }
}
