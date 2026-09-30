import Foundation
import Testing

@testable import HubCore

struct OutputSettingsTests {
  @Test func defaultsToPicturesAndRemembersTheChoice() throws {
    let defaults = try #require(UserDefaults(suiteName: "OutputSettingsTests-\(UUID())"))
    let store = OutputSettingsStore(defaults: defaults)
    #expect(store.folder() == OutputSettingsStore.defaultFolder)
    #expect(OutputSettingsStore.defaultFolder.lastPathComponent == "DT Hub")

    store.setFolder(URL(fileURLWithPath: "/tmp/renders", isDirectory: true))
    #expect(OutputSettingsStore(defaults: defaults).folder().path == "/tmp/renders")
  }
}
