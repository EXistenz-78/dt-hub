import Foundation
import Testing

@testable import HubKit

struct CUMeterPresentationTests {
  let italian = Locale(identifier: "it_IT")
  let english = Locale(identifier: "en_US")

  func pass(_ title: String, _ cu: Int?, limits: CULimits = .standard) -> CUPassReading {
    CUPassReading(title: title, reading: cu.map { CUReading(cu: $0, limits: limits) })
  }

  @Test func theCompactTextFollowsTheLocale() {
    #expect(CUMeterPresentation(passes: [pass("", 32_400)], locale: italian).compact == "32,4k / 40k")
    #expect(CUMeterPresentation(passes: [pass("", 32_400)], locale: english).compact == "32.4k / 40k")
  }

  @Test func aWholeNumberOfThousandsHasNoDecimal() {
    #expect(CUMeterPresentation(passes: [pass("", 40_000)], locale: english).compact == "40k / 40k")
  }

  @Test func noEstimateShowsADash() {
    #expect(CUMeterPresentation(passes: [pass("", nil)], locale: english).compact == "—")
    #expect(CUMeterPresentation(passes: [], locale: english).compact == "—")
    #expect(CUMeterPresentation(passes: [pass("", nil)], locale: english).state == nil)
  }

  @Test func theHeaviestPassWins() {
    let result = CUMeterPresentation(passes: [pass("a", 10_000), pass("b", 30_000), pass("c", nil)], locale: english)
    #expect(result.heaviest?.title == "b")
    #expect(result.compact == "30k / 40k")
  }

  @Test func onATieTheFirstPassWins() {
    let result = CUMeterPresentation(passes: [pass("a", 10_000), pass("b", 10_000)], locale: english)
    #expect(result.heaviest?.title == "a")
  }

  @Test func overTheLimitIsRedAndTheBarIsCapped() {
    let result = CUMeterPresentation(passes: [pass("", 90_000)], locale: english)
    #expect(result.state == .over)
    #expect(result.fraction == 1.25)
  }

  @Test func theFractionIsTheShareOfTheLimit() {
    #expect(CUMeterPresentation(passes: [pass("", 20_000)], locale: english).fraction == 0.5)
  }

  @Test func belowTheLimitTheValueIsTruncatedAndOverItIsRoundedUp() {
    #expect(CUMeterPresentation(passes: [pass("", 39_972)], locale: italian).compact == "39,9k / 40k")
    #expect(CUMeterPresentation(passes: [pass("", 40_001)], locale: italian).compact == "40,1k / 40k")
  }
}
