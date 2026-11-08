import Foundation

/// Asks the user for a yes. The answer is false for a refusal; an implementation must return promptly when its
/// task is cancelled (the gate cancels it when the time is up) and take its box off the screen.
@MainActor
public protocol ConsentPrompter: AnyObject, Sendable {
  func ask(_ summary: String, timeoutSeconds: Int) async -> Bool
}

public enum AuthorizeResult: Equatable, Sendable {
  case allowed
  case denied(String)
}

/// The only question the app ever asks an agent's request (spec §6): a single request above the threshold,
/// while the user has not authorised the session. An exhausted budget is refused at once, without asking.
@MainActor
public final class ConsentGate {
  private let ledger: BudgetLedger
  private let settings: @MainActor () -> RemoteControlSettings
  private let prompter: any ConsentPrompter

  public init(ledger: BudgetLedger, settings: @escaping @MainActor () -> RemoteControlSettings, prompter: any ConsentPrompter) {
    self.ledger = ledger
    self.settings = settings
    self.prompter = prompter
  }

  public func authorize(_ plan: AgentRunPlan, summary: String) async -> AuthorizeResult {
    if case .exhausted(let used, let limit, let unit) = ledger.check(images: plan.images, cu: plan.estimatedCU) {
      let what = unit == .images ? "images" : "compute units"
      return .denied("Budget exhausted: \(used) of \(limit) \(what) used. Ask the user to raise the budget in DT Hub › Remote control.")
    }
    let current = settings()
    guard plan.images > current.confirmThreshold, !ledger.isConfirmed else { return .allowed }
    let seconds = current.confirmTimeoutSeconds
    let prompter = self.prompter
    enum Outcome { case answered(Bool), timedOut }
    let outcome = await withTaskGroup(of: Outcome.self) { group in
      group.addTask { .answered(await prompter.ask(summary, timeoutSeconds: seconds)) }
      group.addTask {
        try? await Task.sleep(for: .seconds(seconds))
        return .timedOut
      }
      let first = await group.next() ?? .timedOut
      group.cancelAll()
      return first
    }
    switch outcome {
    case .answered(true): return .allowed
    case .answered(false): return .denied("The user refused: \(summary).")
    case .timedOut:
      return .denied("Confirmation not received within \(seconds) s, request refused: \(summary). Ask the user to authorise the session in DT Hub › Remote control.")
    }
  }
}
