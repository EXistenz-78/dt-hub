import Testing

@testable import HubCore

struct OnboardingFlowTests {
  @Test func startsOnTheWelcomeStep() {
    let flow = OnboardingFlow()
    #expect(flow.step == .welcome)
    #expect(flow.isFirst)
    #expect(!flow.isLast)
  }

  @Test func backOnTheFirstStepStaysThere() {
    var flow = OnboardingFlow()
    flow.back()
    #expect(flow.step == .welcome)
  }

  @Test func nextFiveTimesEndsOnDoneAndStaysThere() {
    var flow = OnboardingFlow()
    for _ in 0..<5 { flow.next() }
    #expect(flow.step == .done)
    #expect(flow.isLast)
  }

  @Test func walksTheStepsInOrder() {
    var flow = OnboardingFlow()
    var seen = [flow.step]
    for _ in 0..<4 {
      flow.next()
      seen.append(flow.step)
    }
    #expect(seen == [.welcome, .server, .output, .language, .done])
    flow.back()
    #expect(flow.step == .language)
  }
}
