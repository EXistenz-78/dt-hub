import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct ControlStoreQueueTests {
  func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ControlStoreQueueTests-\(UUID())", isDirectory: true)
  }

  func store(in root: URL) -> ControlStore {
    ControlStore(
      storage: FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true)),
      fileURL: root.appendingPathComponent("control.json"))
  }

  func filled(in root: URL) throws -> ControlStore {
    let store = store(in: root)
    try store.setImage(data: pictureData(width: 300, height: 200), name: "cat.png", source: .pasteboard)
    try store.addMoodboardImage(data: pictureData(width: 40, height: 40), name: "a.png", source: .pasteboard)
    try store.addMoodboardImage(data: pictureData(width: 50, height: 50), name: "b.png", source: .pasteboard)
    store.setStrength(0.55)
    store.setZoom(1.4)
    return store
  }

  @Test func captureThenRestoreGivesTheSameState() throws {
    let root = folder()
    let store = try filled(in: root)
    let before = store.inputs
    let entryFolder = root.appendingPathComponent("entry")
    let captured = try store.captureForQueue(into: entryFolder)
    store.clear()
    #expect(store.inputs.image == nil)
    try store.restoreFromQueue(captured, from: entryFolder)
    #expect(store.inputs == before)
    #expect(store.inputs.moodboard.count == 2)
    #expect(store.inputs.strength == 0.55)
    #expect(store.inputs.framing.zoom == 1.4)
    let url = try #require(store.startImageURL)
    #expect(FileManager.default.fileExists(atPath: url.path))
  }

  @Test func restoreIsOneUndoStep() throws {
    let root = folder()
    let store = try filled(in: root)
    let entryFolder = root.appendingPathComponent("entry")
    let captured = try store.captureForQueue(into: entryFolder)
    store.clear()
    let empty = store.inputs
    try store.restoreFromQueue(captured, from: entryFolder)
    store.undo()
    #expect(store.inputs == empty)
  }

  @Test func restoredFilesSurviveGarbageCollection() throws {
    let root = folder()
    let store = try filled(in: root)
    let entryFolder = root.appendingPathComponent("entry")
    let captured = try store.captureForQueue(into: entryFolder)
    store.clear()
    try store.restoreFromQueue(captured, from: entryFolder)
    store.setStrength(0.3)
    let url = try #require(store.startImageURL)
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(store.moodboardURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
  }

  @Test func captureWithoutImagesWritesNothing() throws {
    let root = folder()
    let store = store(in: root)
    let entryFolder = root.appendingPathComponent("entry")
    let captured = try store.captureForQueue(into: entryFolder)
    #expect(captured == ControlInputs())
    let items = (try? FileManager.default.contentsOfDirectory(atPath: entryFolder.path)) ?? []
    #expect(items.isEmpty)
  }

  @Test func restoreWithAMissingFileThrowsUnreadableAndChangesNothing() throws {
    let root = folder()
    let store = try filled(in: root)
    let entryFolder = root.appendingPathComponent("entry")
    let captured = try store.captureForQueue(into: entryFolder)
    let victim = try #require(captured.moodboard.first).image.fileName
    try FileManager.default.removeItem(at: entryFolder.appendingPathComponent(victim))
    store.clear()
    let empty = store.inputs
    #expect(throws: ControlError.unreadable(victim)) {
      try store.restoreFromQueue(captured, from: entryFolder)
    }
    #expect(store.inputs == empty)
  }
}
