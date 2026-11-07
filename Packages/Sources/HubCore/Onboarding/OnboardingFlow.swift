/// The steps of the first-launch setup, in order.
public enum OnboardingStep: Int, CaseIterable, Sendable {
  case welcome, server, output, language, done
}

/// Where the user is in the setup: moves one step at a time and never leaves the first or the last.
public struct OnboardingFlow: Sendable {
  public private(set) var step: OnboardingStep = .welcome

  public init() {}

  public var isFirst: Bool { step == OnboardingStep.allCases.first }
  public var isLast: Bool { step == OnboardingStep.allCases.last }

  public mutating func next() {
    if let following = OnboardingStep(rawValue: step.rawValue + 1) { step = following }
  }

  public mutating func back() {
    if let previous = OnboardingStep(rawValue: step.rawValue - 1) { step = previous }
  }
}
