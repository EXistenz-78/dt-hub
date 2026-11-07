import Foundation
import Testing

@testable import HubCore

struct OnboardingGateTests {
  private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "OnboardingGateTests-\(UUID().uuidString)")!
  }

  @Test func showsOnAFreshInstall() {
    #expect(OnboardingGate.shouldShow(defaults: freshDefaults()))
  }

  @Test func hidesAfterCompletion() {
    let defaults = freshDefaults()
    OnboardingGate.markCompleted(defaults: defaults)
    #expect(!OnboardingGate.shouldShow(defaults: defaults))
  }

  @Test func hidesWhenAConnectionWasSaved() {
    let defaults = freshDefaults()
    ConnectionSettingsStore(defaults: defaults).save(.default)
    #expect(!OnboardingGate.shouldShow(defaults: defaults))
  }

  @Test func hidesWhenOnlyTheManagedServerWasSaved() {
    let defaults = freshDefaults()
    ManagedServerSettingsStore(defaults: defaults).save(.default)
    #expect(!OnboardingGate.shouldShow(defaults: defaults))
  }

  @Test func anUnreadableCompletedValueCountsAsNotCompleted() {
    let defaults = freshDefaults()
    defaults.set("x", forKey: OnboardingGate.completedKey)
    #expect(OnboardingGate.shouldShow(defaults: defaults))
  }
}
