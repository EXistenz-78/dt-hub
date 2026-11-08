/// What an agent may do (spec 2026-11-08 §6). Tools outside the mode are not even listed.
public enum AccessMode: String, Codable, Sendable, CaseIterable, Comparable {
  case readOnly
  case editFields
  case full

  private var rank: Int {
    switch self {
    case .readOnly: 0
    case .editFields: 1
    case .full: 2
    }
  }

  public static func < (lhs: AccessMode, rhs: AccessMode) -> Bool { lhs.rank < rhs.rank }
}
