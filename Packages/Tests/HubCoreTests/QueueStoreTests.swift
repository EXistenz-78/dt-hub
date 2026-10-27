import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct QueueStoreTests {
  func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("QueueStoreTests-\(UUID())", isDirectory: true)
  }

  func entry(_ prompt: String, status: QueueStatus = .pending) -> QueueEntry {
    QueueEntry(status: status, preset: Preset(name: "", prompt: prompt))
  }

  @Test func addPersistsAndReloads() {
    let root = folder()
    let store = QueueStore(folder: root)
    store.add(entry("one"))
    store.add(entry("two"))
    let again = QueueStore(folder: root)
    #expect(again.entries.map(\.preset.prompt) == ["one", "two"])
  }

  @Test func runningIsReadAsPendingOnLoad() {
    let root = folder()
    let store = QueueStore(folder: root)
    store.add(entry("one", status: .running))
    #expect(QueueStore(folder: root).entries.first?.status == .pending)
  }

  @Test func removeDeletesTheEntryFolder() throws {
    let root = folder()
    let store = QueueStore(folder: root)
    let item = entry("one")
    store.add(item)
    try FileManager.default.createDirectory(at: store.folder(for: item.id), withIntermediateDirectories: true)
    store.remove(id: item.id)
    #expect(store.entries.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.folder(for: item.id).path))
  }

  @Test func removingAGuidedEntryDeletesPluginFiles() throws {
    let store = QueueStore(folder: folder())
    var item = entry("guided")
    item.pipeline = .guided(
      pluginID: "tiled-upscale", name: "Tiled Upscale", passes: 4, state: try #require(QueueSnapshot(jsonObject: ["image": "source.png"])))
    store.add(item)
    let file = store.folder(for: item.id).appendingPathComponent("plugin/source.png")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("png".utf8).write(to: file)
    store.remove(id: item.id)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(!FileManager.default.fileExists(atPath: store.folder(for: item.id).path))
  }

  @Test func clearDeletesEverything() throws {
    let root = folder()
    let store = QueueStore(folder: root)
    let first = entry("one")
    store.add(first)
    store.add(entry("two"))
    try FileManager.default.createDirectory(at: store.folder(for: first.id), withIntermediateDirectories: true)
    store.clear()
    #expect(store.entries.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.folder(for: first.id).path))
    #expect(QueueStore(folder: root).entries.isEmpty)
  }

  @Test func moveReorders() {
    let store = QueueStore(folder: folder())
    for name in ["a", "b", "c"] { store.add(entry(name)) }
    store.move(from: IndexSet(integer: 2), to: 0)
    #expect(store.entries.map(\.preset.prompt) == ["c", "a", "b"])
  }

  @Test func firstPendingSkipsFinishedEntries() {
    let store = QueueStore(folder: folder())
    let done = entry("a")
    store.add(done)
    store.add(entry("b"))
    store.setStatus(.done, for: done.id)
    #expect(store.firstPending?.preset.prompt == "b")
  }

  @Test func switchToAnotherFolderShowsItsEntries() {
    let one = folder()
    let two = folder()
    let store = QueueStore(folder: one)
    store.add(entry("in one"))
    store.switchTo(folder: two)
    #expect(store.entries.isEmpty)
    store.add(entry("in two"))
    store.switchTo(folder: one)
    #expect(store.entries.map(\.preset.prompt) == ["in one"])
  }

  @Test func aCorruptFileGivesAnEmptyQueueAndKeepsTheFolders() throws {
    let root = folder()
    let store = QueueStore(folder: root)
    let item = entry("one")
    store.add(item)
    let kept = store.folder(for: item.id)
    try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
    try Data("{not json".utf8).write(to: root.appendingPathComponent("queue.json"))
    let again = QueueStore(folder: root)
    #expect(again.entries.isEmpty)
    #expect(FileManager.default.fileExists(atPath: kept.path))
  }

  @Test func copyingImagesRewritesPaths() throws {
    let root = folder()
    let store = QueueStore(folder: root)
    let source = FileManager.default.temporaryDirectory.appendingPathComponent("sphere-\(UUID()).png")
    try Data("png".utf8).write(to: source)
    let id = UUID()
    let step = PipelineStep(
      title: "t", preset: "p", moodboard: [PluginImageRef(name: "sphere.png", path: source.path)])
    let copied = try store.copyingImages(of: [step], forEntry: id)
    let path = try #require(copied.first?.moodboard?.first?.path)
    #expect(path.hasPrefix(store.folder(for: id).path))
    #expect(FileManager.default.fileExists(atPath: path))
    #expect(copied.first?.moodboard?.first?.name == "sphere.png")
  }

  @Test func copyingImagesWithAMissingFileThrows() {
    let store = QueueStore(folder: folder())
    let step = PipelineStep(moodboard: [PluginImageRef(name: "x.png", path: "/nonexistent/x.png")])
    #expect(throws: (any Error).self) { try store.copyingImages(of: [step], forEntry: UUID()) }
  }

  @Test func noFolderMeansNoPersistence() {
    let store = QueueStore(folder: nil)
    store.add(entry("memory"))
    #expect(store.entries.count == 1)
    #expect(store.folder(for: UUID()).path.hasPrefix(FileManager.default.temporaryDirectory.path))
  }
}
