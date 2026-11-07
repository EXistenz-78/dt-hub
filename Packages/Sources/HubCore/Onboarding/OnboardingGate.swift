import Foundation

/// When the first-launch setup sheet is shown. A clean install sees it once; whoever already saved a server (an update
/// from an older version) never does.
public enum OnboardingGate {
  public static let completedKey = "onboarding.completed"

  public static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
    if defaults.bool(forKey: completedKey) { return false }
    if defaults.data(forKey: ConnectionSettingsStore.key) != nil { return false }
    if defaults.data(forKey: ManagedServerSettingsStore.key) != nil { return false }
    return true
  }

  public static func markCompleted(defaults: UserDefaults = .standard) {
    defaults.set(true, forKey: completedKey)
  }
}
