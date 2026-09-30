import Foundation
import Testing

@testable import HubCore

struct ConnectionSettingsTests {
  @Test func defaultsPointAtTheLocalDrawThingsServer() {
    #expect(ConnectionSettings.default == ConnectionSettings(host: "localhost", port: 7859, useTLS: true))
    #expect(ConnectionSettings.default.validationError == nil)
  }

  @Test(arguments: [
    ("", ConnectionSettings.ValidationError.emptyHost),
    ("   ", .emptyHost),
    ("http://localhost", .invalidHost),
    ("local host", .invalidHost),
    ("localhost/api", .invalidHost),
  ])
  func rejectsBadHosts(host: String, expected: ConnectionSettings.ValidationError) {
    #expect(ConnectionSettings(host: host).validationError == expected)
  }

  @Test(arguments: [0, -1, 65536])
  func rejectsPortsOutOfRange(port: Int) {
    #expect(ConnectionSettings(port: port).validationError == .invalidPort)
  }

  @Test func acceptsIPAddressesAndTrimsSpaces() {
    let settings = ConnectionSettings(host: " 192.168.1.20 ", port: 7859)
    #expect(settings.validationError == nil)
    #expect(settings.trimmedHost == "192.168.1.20")
  }

  @Test func storeRoundTripsAndFallsBackToDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: "ConnectionSettingsTests-\(UUID())"))
    let store = ConnectionSettingsStore(defaults: defaults)
    #expect(store.load() == .default)

    let custom = ConnectionSettings(host: "studio.local", port: 7860, useTLS: false)
    store.save(custom)
    #expect(ConnectionSettingsStore(defaults: defaults).load() == custom)

    defaults.set(Data("garbage".utf8), forKey: ConnectionSettingsStore.key)
    #expect(store.load() == .default)
  }
}
