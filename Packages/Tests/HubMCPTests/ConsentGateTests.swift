import Testing

@testable import HubMCP

@MainActor
final class FakePrompter: ConsentPrompter {
  var answer: Bool?  // nil = never answers (waits until cancelled)
  private(set) var asked: [String] = []

  func ask(_ summary: String, timeoutSeconds: Int) async -> Bool {
    asked.append(summary)
    if let answer { return answer }
    try? await Task.sleep(for: .seconds(3600))
    return false
  }
}

@MainActor
struct ConsentGateTests {
  func make(threshold: Int = 20, budget: Int = 200, timeout: Int = 60, answer: Bool? = true)
    -> (ConsentGate, BudgetLedger, FakePrompter)
  {
    var s = RemoteControlSettings()
    s.confirmThreshold = threshold
    s.imageBudget = budget
    s.confirmTimeoutSeconds = timeout
    let ledger = BudgetLedger(settings: { s })
    let prompter = FakePrompter()
    prompter.answer = answer
    return (ConsentGate(ledger: ledger, settings: { s }, prompter: prompter), ledger, prompter)
  }

  @Test func belowThresholdNeverAsks() async {
    let (gate, _, prompter) = make()
    #expect(await gate.authorize(AgentRunPlan(images: 20), summary: "20 images") == .allowed)
    #expect(prompter.asked.isEmpty)
  }

  @Test func aboveThresholdUnconfirmedAsksAndAllowsOnYes() async {
    let (gate, _, prompter) = make()
    #expect(await gate.authorize(AgentRunPlan(images: 80), summary: "80 images") == .allowed)
    #expect(prompter.asked == ["80 images"])
  }

  @Test func userRefusalIsDenied() async {
    let (gate, _, _) = make(answer: false)
    guard case .denied(let reason) = await gate.authorize(AgentRunPlan(images: 80), summary: "80 images") else {
      Issue.record("expected denial")
      return
    }
    #expect(reason.contains("refused"))
  }

  @Test func aboveThresholdConfirmedBudgetDoesNotAsk() async {
    let (gate, ledger, prompter) = make()
    ledger.confirm()
    #expect(await gate.authorize(AgentRunPlan(images: 80), summary: "80 images") == .allowed)
    #expect(prompter.asked.isEmpty)
  }

  @Test func noAnswerWithinTimeoutIsDenied() async {
    let (gate, _, _) = make(timeout: 0, answer: nil)
    guard case .denied(let reason) = await gate.authorize(AgentRunPlan(images: 80), summary: "80 images") else {
      Issue.record("expected denial")
      return
    }
    #expect(reason.contains("0 s") || reason.contains("not received"))
  }

  @Test func exhaustedBudgetIsDeniedWithoutAsking() async {
    let (gate, ledger, prompter) = make(budget: 200)
    _ = ledger.reserve(images: 200, cu: nil)
    guard case .denied(let reason) = await gate.authorize(AgentRunPlan(images: 1), summary: "1 image") else {
      Issue.record("expected denial")
      return
    }
    #expect(reason.contains("200 of 200"))
    #expect(prompter.asked.isEmpty)
  }
}
