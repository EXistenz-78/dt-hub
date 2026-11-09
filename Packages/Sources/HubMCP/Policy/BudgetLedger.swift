import Foundation
import Observation

public enum BudgetUnit: Equatable, Sendable {
  case images
  case computeUnits
}

public enum BudgetResult: Equatable, Sendable {
  case granted
  case exhausted(used: Int, limit: Int, unit: BudgetUnit)
}

/// What the agent has used in this session against the budget the user set (spec §6). Everything runs on the
/// main actor, so two requests in a row see each other's reservation.
@MainActor
@Observable
public final class BudgetLedger {
  public private(set) var usedImages = 0
  public private(set) var usedCU = 0
  /// True once the user authorised the session in the panel: requests above the threshold stop asking.
  public private(set) var isConfirmed = false
  @ObservationIgnored private let settings: @MainActor () -> RemoteControlSettings

  public init(settings: @escaping @MainActor () -> RemoteControlSettings) {
    self.settings = settings
  }

  /// Whether `images` (and `cu`) would fit, without using anything.
  public func check(images: Int, cu: Int?) -> BudgetResult {
    let current = settings()
    if usedImages + images > current.imageBudget {
      return .exhausted(used: usedImages, limit: current.imageBudget, unit: .images)
    }
    if let limit = current.cuBudget, let cu, usedCU + cu > limit {
      return .exhausted(used: usedCU, limit: limit, unit: .computeUnits)
    }
    return .granted
  }

  public func reserve(images: Int, cu: Int?) -> BudgetResult {
    let result = check(images: images, cu: cu)
    guard result == .granted else { return result }
    usedImages += images
    usedCU += cu ?? 0
    return .granted
  }

  public func refund(images: Int, cu: Int?) {
    usedImages = max(0, usedImages - images)
    usedCU = max(0, usedCU - (cu ?? 0))
  }

  public func confirm() { isConfirmed = true }

  public func reset() {
    usedImages = 0
    usedCU = 0
    isConfirmed = false
  }
}
