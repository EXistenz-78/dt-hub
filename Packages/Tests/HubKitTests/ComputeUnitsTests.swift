import Foundation
import Testing

@testable import HubKit

struct CULimitsTests {
  let standard = CULimits.standard

  @Test func theStandardLimitsAreTheOfficialDefaults() {
    #expect(standard.plus == 40_000)
    #expect(standard.community == 10_000)
    #expect(standard.limit == 40_000)
  }

  @Test func boostsNeededRoundUpInStepsOf20000() {
    #expect(standard.boostsNeeded(for: 39_972) == 0)
    #expect(standard.boostsNeeded(for: 40_000) == 0)
    #expect(standard.boostsNeeded(for: 40_001) == 1)
    #expect(standard.boostsNeeded(for: 60_000) == 1)
    #expect(standard.boostsNeeded(for: 60_001) == 2)
  }

  @Test func eachBoostRaisesTheLimitBy20000() {
    #expect(standard.limit(afterBoosts: 0) == 40_000)
    #expect(standard.limit(afterBoosts: 2) == 80_000)
  }
}

struct CUReadingTests {
  @Test func belowNinetyPercentIsOK() {
    #expect(CUReading(cu: 35_999, limits: .standard).state == .ok)
  }

  @Test func fromNinetyPercentToTheLimitIsNear() {
    #expect(CUReading(cu: 36_000, limits: .standard).state == .near)
    #expect(CUReading(cu: 40_000, limits: .standard).state == .near)
  }

  @Test func overTheLimitNeedsBoosts() {
    let reading = CUReading(cu: 40_001, limits: .standard)
    #expect(reading.state == .over)
    #expect(reading.boosts == 1)
    #expect(reading.limit == 40_000)
  }

  @Test func aPolicyLimitIsUsed() {
    let policy = CULimits(plus: 20_000, community: 10_000, expiresAt: nil)
    #expect(CUReading(cu: 20_001, limits: policy).state == .over)
    #expect(CUReading(cu: 20_000, limits: policy).boosts == 0)
  }
}
