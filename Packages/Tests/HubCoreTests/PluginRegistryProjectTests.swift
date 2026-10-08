import Foundation
import HubKit
import Testing

@testable import HubCore

/// The `project` message: every loaded plug-in is told which project is open (spec §5.5).
@MainActor
struct PluginRegistryProjectTests {
  let root = PluginFixture.folder()
  var settingsFile: URL { root.deletingLastPathComponent().appendingPathComponent("settings-\(root.lastPathComponent).json") }

  func registry(loader: FakeLoader, enabled: Set<String>) -> PluginRegistry {
    let settings = PluginSettingsStore(fileURL: settingsFile)
    settings.save(enabled)
    return PluginRegistry(folder: PluginFolder(root: root), settings: settings, loader: loader, tempFolder: root)
  }

  func settle() async { try? await Task.sleep(for: .milliseconds(40)) }

  func project(_ name: String = "Campagna") -> Project {
    Project(name: name, folder: root.deletingLastPathComponent().appendingPathComponent("out-\(root.lastPathComponent)/\(name)"))
  }

  private func projectMessages(of plugin: FakeLoadedPlugin) throws -> [[String: Any]] {
    try plugin.sent.filter { PluginMessageType.of($0) == "project" }
      .map { try #require(try JSONSerialization.jsonObject(with: $0) as? [String: Any]) }
  }

  @Test func everyLoadedPluginHearsAboutTheProjectEvenIfItIsOff() async throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    try PluginFixture.bundle(in: root, id: "b", name: "B")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a", "b"])
    registry.start()
    registry.setActive("b", false)
    let project = project()
    registry.projectChanged(project, adoptLegacy: true)
    await settle()
    for id in ["a", "b"] {
      let messages = try projectMessages(of: try #require(loader.plugins[id]))
      #expect(messages.count == 1, "\(id)")
      #expect(messages.first?["name"] as? String == "Campagna")
      #expect(messages.first?["folder"] as? String == project.pluginFolder(id).path)
      #expect(messages.first?["adoptLegacy"] as? Bool == true)
      var isFolder: ObjCBool = false
      #expect(FileManager.default.fileExists(atPath: project.pluginFolder(id).path, isDirectory: &isFolder) && isFolder.boolValue)
    }
  }

  @Test func aPluginThatIsNotLoadedHearsNothing() async throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    try PluginFixture.bundle(in: root, id: "off", name: "Off")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.start()
    let project = project()
    registry.projectChanged(project, adoptLegacy: false)
    await settle()
    #expect(loader.plugins["off"] == nil)
    #expect(!FileManager.default.fileExists(atPath: project.pluginFolder("off").path))
  }

  @Test func aPluginThatDoesNotKnowTheMessageGetsOneNoteOnly() async throws {
    try PluginFixture.bundle(in: root, id: "old", name: "Old Plug-in")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["old"])
    registry.start()
    let plugin = try #require(loader.plugins["old"])
    plugin.answer = PluginMessageType.bare(PluginMessageType.unsupported)
    registry.projectChanged(project("A"), adoptLegacy: false)
    await settle()
    registry.projectChanged(project("B"), adoptLegacy: false)
    await settle()
    let notes = registry.notices.filter { $0.pluginID == "old" }
    #expect(notes.count == 1)
    #expect(notes.first?.isError == false)
    #expect(notes.first?.text.contains("Old Plug-in") == true)
    #expect(registry.latestNotice?.pluginID == "old")
  }

  @Test func aPluginThatKnowsTheMessageGetsNoNote() async throws {
    try PluginFixture.bundle(in: root, id: "new", name: "New")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["new"])
    registry.start()
    registry.projectChanged(project(), adoptLegacy: false)
    await settle()
    #expect(registry.notices.isEmpty)
  }

  @Test func theNoteIsInItalianAndEnglish() {
    #expect(PluginRegistry.noProjectStateText(for: "X", italian: false) == "The plug-in X does not keep its state per project.")
    #expect(PluginRegistry.noProjectStateText(for: "X", italian: true) == "Il plug-in X non separa lo stato per progetto.")
  }

  @Test func atLaunchTheLoadedPluginsAreToldTheCurrentProject() async throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    let project = project()
    registry.currentProject = { (project, adoptLegacy: false) }
    registry.start()
    await settle()
    let messages = try projectMessages(of: try #require(loader.plugins["a"]))
    #expect(messages.count == 1)
    #expect(messages.first?["folder"] as? String == project.pluginFolder("a").path)
  }

  @Test func withoutACurrentProjectNothingIsSentAtLaunch() async throws {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let loader = FakeLoader()
    let registry = registry(loader: loader, enabled: ["a"])
    registry.currentProject = { nil }
    registry.start()
    await settle()
    #expect(try projectMessages(of: try #require(loader.plugins["a"])).isEmpty)
  }
}
