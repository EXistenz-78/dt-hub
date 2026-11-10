import Foundation
import HubKit
import Testing

@testable import HubCore

/// The plug-ins' list of language models: answered from the last scan, so a tab change never waits for the disk.
@MainActor
struct LanguageModelManagerCacheTests {
  let helper = LanguageModelManagerServerTests()

  func addModel(_ name: String, to root: URL) throws {
    let dir = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try "{}".write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
    try Data(count: 500).write(to: dir.appendingPathComponent("w.safetensors"))
  }

  @Test func theFirstCallScansAndTheLaterOnesAnswerFromTheLastScan() throws {
    let root = try LanguageModelManagerTests().folder()
    let manager = try helper.make(server: FakeServerService(), root: root, backend: .folder)
    #expect(manager.availableModelsWithoutWaiting().map(\.name) == ["text-model", "vision-model"])
    try addModel("new-model", to: root)
    // The disk changed, the answer does not wait for it.
    #expect(manager.availableModelsWithoutWaiting().map(\.name) == ["text-model", "vision-model"])
  }

  @Test func aModelAddedMeanwhileIsFoundByTheBackgroundScanAndAnnounced() async throws {
    let root = try LanguageModelManagerTests().folder()
    let manager = try helper.make(server: FakeServerService(), root: root, backend: .folder)
    var announced = 0
    manager.onFolderModelsChanged = { announced += 1 }
    _ = manager.availableModelsWithoutWaiting()
    try addModel("new-model", to: root)
    _ = manager.availableModelsWithoutWaiting()  // starts the rescan
    for _ in 0..<100 where announced == 0 { try await Task.sleep(for: .milliseconds(20)) }
    #expect(announced == 1)
    #expect(manager.availableModelsWithoutWaiting().map(\.name) == ["new-model", "text-model", "vision-model"])
  }

  @Test func aRescanThatFindsNothingNewAnnouncesNothing() async throws {
    let root = try LanguageModelManagerTests().folder()
    let manager = try helper.make(server: FakeServerService(), root: root, backend: .folder)
    var announced = 0
    manager.onFolderModelsChanged = { announced += 1 }
    _ = manager.availableModelsWithoutWaiting()
    _ = manager.availableModelsWithoutWaiting()
    try await Task.sleep(for: .milliseconds(300))
    #expect(announced == 0)
  }

  @Test func aChangedFolderIsScannedAgainAtOnce() throws {
    let first = try LanguageModelManagerTests().folder()
    let second = try LanguageModelManagerTests().folder()
    try addModel("only-in-second", to: second)
    let manager = try helper.make(server: FakeServerService(), root: first, backend: .folder)
    #expect(manager.availableModelsWithoutWaiting().count == 2)
    manager.settings.folder = second.path
    #expect(manager.availableModelsWithoutWaiting().map(\.name) == ["only-in-second", "text-model", "vision-model"])
  }
}
