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
    ("localhost:7859", .invalidHost),
    ("192.168.1.20:7859", .invalidHost),
    ("[::1]", .invalidHost),
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

  @Test func acceptsABareIPv6Address() {
    #expect(ConnectionSettings(host: "::1").validationError == nil)
  }

  @Test(arguments: [("7859", 7859), (" 7860 ", 7860), ("99999", 99999)])
  func readsThePortFromText(text: String, port: Int) {
    #expect(ConnectionSettings.parsePort(text) == port)
  }

  @Test(arguments: ["", "abc", "78 59", "-1", "7859x"])
  func rejectsPortTextThatIsNotANumber(text: String) {
    #expect(ConnectionSettings.parsePort(text) == nil)
  }
}
