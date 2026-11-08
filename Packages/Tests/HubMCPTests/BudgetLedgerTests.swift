import Testing

@testable import HubMCP

@MainActor
struct BudgetLedgerTests {
  func ledger(images: Int = 10, cu: Int? = nil) -> BudgetLedger {
    var s = RemoteControlSettings()
    s.imageBudget = images
    s.cuBudget = cu
    return BudgetLedger(settings: { s })
  }

  @Test func reserveWithinLimitIsGranted() {
    let l = ledger()
    #expect(l.reserve(images: 10, cu: nil) == .granted)
    #expect(l.usedImages == 10)
  }

  @Test func reserveBeyondLimitIsExhaustedWithoutChangingUsed() {
    let l = ledger()
    _ = l.reserve(images: 4, cu: nil)
    #expect(l.reserve(images: 7, cu: nil) == .exhausted(used: 4, limit: 10, unit: .images))
    #expect(l.usedImages == 4)
  }

  @Test func twoConsecutiveReservesCannotBothPassTheLastSlots() {
    let l = ledger()
    #expect(l.reserve(images: 6, cu: nil) == .granted)
    #expect(l.reserve(images: 6, cu: nil) != .granted)
  }

  @Test func checkDoesNotChangeUsage() {
    let l = ledger()
    #expect(l.check(images: 5, cu: nil) == .granted)
    #expect(l.usedImages == 0)
  }

  @Test func refundGivesImagesBack() {
    let l = ledger()
    _ = l.reserve(images: 8, cu: 30)
    l.refund(images: 8, cu: 30)
    #expect(l.usedImages == 0)
    #expect(l.usedCU == 0)
  }

  @Test func resetClearsUsageAndConfirmation() {
    let l = ledger()
    _ = l.reserve(images: 3, cu: nil)
    l.confirm()
    l.reset()
    #expect(l.usedImages == 0)
    #expect(l.isConfirmed == false)
  }

  @Test func cuBudgetAppliesOnlyWhenSet() {
    #expect(ledger(cu: nil).reserve(images: 1, cu: 9999) == .granted)
    let l = ledger(cu: 100)
    #expect(l.reserve(images: 1, cu: 60) == .granted)
    #expect(l.reserve(images: 1, cu: 60) == .exhausted(used: 60, limit: 100, unit: .computeUnits))
  }
}
