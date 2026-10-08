import Foundation
import HubKit
import Testing

@testable import HubCore

/// `ControlStore.switchTo`: Control follows the project that is open.
@MainActor
struct ControlStoreProjectTests {
  private func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("CSProject-\(UUID())", isDirectory: true)
  }

  private func storage(_ root: URL) -> FileReferenceStorage {
    FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true))
  }

  private func file(_ root: URL) -> URL { root.appendingPathComponent("control.json") }

  private func copies(_ root: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Control").path)) ?? []).sorted()
  }

  private func put(_ name: String, in store: ControlStore) throws {
    try store.setImage(data: pictureData(width: 30, height: 20), name: name, source: .pasteboard)
  }

  @Test func eachProjectKeepsItsOwnState() throws {
    let (a, b) = (root(), root())
    let store = ControlStore(storage: storage(a), fileURL: file(a))
    try put("a.png", in: store)
    store.switchTo(storage: storage(b), fileURL: file(b))
    #expect(store.inputs.image == nil)
    store.switchTo(storage: storage(a), fileURL: file(a))
    #expect(store.inputs.image?.name == "a.png")
  }

  @Test func theHistoryIsClearedWhenTheProjectChanges() throws {
    let (a, b) = (root(), root())
    let store = ControlStore(storage: storage(a), fileURL: file(a))
    try put("a.png", in: store)
    #expect(store.canUndo)
    store.switchTo(storage: storage(b), fileURL: file(b))
    #expect(!store.canUndo && !store.canRedo)
    store.switchTo(storage: storage(a), fileURL: file(a))
    #expect(!store.canUndo && !store.canRedo)
    #expect(store.notice == nil)
  }

  @Test func theCopiesOfTheOtherProjectAreNotDeleted() throws {
    let (a, b) = (root(), root())
    let store = ControlStore(storage: storage(a), fileURL: file(a))
    try put("a.png", in: store)
    let before = copies(a)
    #expect(before.count == 1)
    store.switchTo(storage: storage(b), fileURL: file(b))
    #expect(copies(a) == before)
  }

  @Test func copiesNothingRefersToInTheNewProjectAreSwept() throws {
    let (a, b) = (root(), root())
    let store = ControlStore(storage: storage(a), fileURL: file(a))
    try FileManager.default.createDirectory(at: b.appendingPathComponent("Control"), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: b.appendingPathComponent("Control/orphan.png"))
    store.switchTo(storage: storage(b), fileURL: file(b))
    #expect(copies(b).isEmpty)
  }

  @Test func aMissingCopyIsDroppedWithANotice() throws {
    let (a, b) = (root(), root())
    let store = ControlStore(storage: storage(a), fileURL: file(a))
    try put("a.png", in: store)
    let copy = try #require(copies(a).first)
    try FileManager.default.removeItem(at: a.appendingPathComponent("Control/\(copy)"))
    store.switchTo(storage: storage(b), fileURL: file(b))
    store.switchTo(storage: storage(a), fileURL: file(a))
    #expect(store.inputs.image == nil)
    #expect(store.notice == .missingAtLaunch(name: "a.png"))
  }

  @Test func aCorruptControlFileGivesEmptyInputs() throws {
    let (a, b) = (root(), root())
    let store = ControlStore(storage: storage(a), fileURL: file(a))
    try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: file(b))
    store.switchTo(storage: storage(b), fileURL: file(b))
    #expect(store.inputs.image == nil && store.inputs.moodboard.isEmpty)
  }

  @Test func changesAfterTheSwitchGoToTheNewProject() throws {
    let (a, b) = (root(), root())
    let store = ControlStore(storage: storage(a), fileURL: file(a))
    try put("a.png", in: store)
    let aBytes = try Data(contentsOf: file(a))
    store.switchTo(storage: storage(b), fileURL: file(b))
    try put("b.png", in: store)
    #expect(try Data(contentsOf: file(a)) == aBytes)
    let saved = try JSONDecoder().decode(ControlInputs.self, from: Data(contentsOf: file(b)))
    #expect(saved.image?.name == "b.png")
    #expect(copies(b).count == 1)
  }

  @Test func theStartImageURLFollowsTheProject() throws {
    let (a, b) = (root(), root())
    let store = ControlStore(storage: storage(a), fileURL: file(a))
    try put("a.png", in: store)
    #expect(store.startImageURL?.path.hasPrefix(a.path) == true)
    store.switchTo(storage: storage(b), fileURL: file(b))
    try put("b.png", in: store)
    #expect(store.startImageURL?.path.hasPrefix(b.path) == true)
  }
}
