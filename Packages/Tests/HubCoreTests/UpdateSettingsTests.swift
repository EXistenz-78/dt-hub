import Foundation
import Testing

@testable import HubCore

struct UpdateSettingsTests {
  /// A suite of its own, so the tests touch nothing of the app's preferences.
  static func defaults() -> UserDefaults {
    let name = "UpdateSettingsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  static let start = Date(timeIntervalSince1970: 1_000_000)

  @Test func checkingAtLaunchIsOnByDefault() {
    #expect(UpdateSettings(defaults: Self.defaults()).checkOnLaunch)
  }

  @Test func aCheckAMinuteAgoDoesNotHoldBackTheLaunchCheck() {
    // What the launch check reads is the switch alone, not the time of the last check.
    var settings = UpdateSettings(defaults: Self.defaults())
    settings.markChecked(at: Self.start)
    #expect(settings.checkOnLaunch)
    #expect(settings.lastCheck == Self.start)
  }

  @Test func theLaunchCheckCanBeSwitchedOff() {
    var settings = UpdateSettings(defaults: Self.defaults())
    settings.checkOnLaunch = false
    #expect(!settings.checkOnLaunch)
  }

  @Test func settingsSurviveANewInstance() {
    let defaults = Self.defaults()
    var settings = UpdateSettings(defaults: defaults)
    settings.markChecked(at: Self.start)
    settings.checkOnLaunch = false
    settings.dismiss([UpdateOffer(item: UpdatePlanTests.item("app", "1.0.0", contract: nil), installed: "0.9.0")])
    let again = UpdateSettings(defaults: defaults)
    #expect(again.lastCheck == Self.start)
    #expect(!again.checkOnLaunch)
    #expect(again.dismissed == ["app": "1.0.0"])
  }
}
