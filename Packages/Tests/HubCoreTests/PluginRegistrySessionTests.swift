import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct PluginRegistrySessionTests {
  let root = PluginFixture.folder()

  private func started(_ loader: FakeLoader) throws -> PluginRegistry {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let settingsFile = root.deletingLastPathComponent().appendingPathComponent("settings-\(root.lastPathComponent).json")
    let settings = PluginSettingsStore(fileURL: settingsFile)
    settings.save(["a"])
    let registry = PluginRegistry(folder: PluginFolder(root: root), settings: settings, loader: loader, tempFolder: root)
    registry.start()
    return registry
  }

  @Test func requestReturnsThePluginsAnswer() async throws {
    let loader = FakeLoader()
    let registry = try started(loader)
    let plugin = try #require(loader.plugins["a"])
    plugin.answer = Data(#"{"done":true}"#.utf8)
    let answer = await registry.request(PluginMessageType.bare("session.next"), to: "a", timeout: .seconds(1))
    #expect(answer == Data(#"{"done":true}"#.utf8))
    #expect(plugin.sentTypes.last == "session.next")
  }

  @Test func requestReturnsNilForAnUnknownPlugin() async throws {
    let registry = try started(FakeLoader())
    #expect(await registry.request(Data("{}".utf8), to: "nope", timeout: .seconds(1)) == nil)
  }

  @Test func requestTimesOutAndReturnsNil() async throws {
    let loader = FakeLoader()
    let registry = try started(loader)
    loader.plugins["a"]?.delay = .seconds(10)
    let started = ContinuousClock.now
    let answer = await registry.request(Data("{}".utf8), to: "a", timeout: .milliseconds(50))
    #expect(answer == nil)
    #expect(ContinuousClock.now - started < .seconds(8), "it must not wait for the plug-in's 10 s")
  }

  @Test func sessionFolderIsInsideTheTempFolderAndRemoved() throws {
    let registry = try started(FakeLoader())
    let folder = registry.sessionFolder()
    #expect(folder.path.hasPrefix(root.path))
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    registry.removeSessionFolder(folder)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
  }

  @Test func removingAFolderOutsideTheTempFolderDoesNothing() throws {
    let registry = try started(FakeLoader())
    let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID())")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    registry.removeSessionFolder(outside)
    #expect(FileManager.default.fileExists(atPath: outside.path))
    try? FileManager.default.removeItem(at: outside)
  }
}
