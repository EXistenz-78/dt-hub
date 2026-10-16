import Foundation
import Testing

@testable import DepthPose

@Suite("DPStore")
struct DPStoreTests {
  private func makeDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "dp-test-\(UUID().uuidString)")!
    return defaults
  }

  private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dps-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func folderStore(_ folder: URL) -> DPStore {
    var store = DPStore(defaults: makeDefaults())
    store.folder = folder
    return store
  }

  @Test func theFirstRunHasBothMapsChosen() {
    #expect(DPStore(defaults: makeDefaults()).load() == DPSelection(depth: true, pose: true))
  }

  @Test func theChoiceIsKeptInTheProjectFolder() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = folderStore(folder)
    store.save(DPSelection(depth: false, pose: true))
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("state.json").path))
    #expect(store.load() == DPSelection(depth: false, pose: true))
  }

  @Test func withoutAFolderItGoesToTheDefaults() {
    let defaults = makeDefaults()
    DPStore(defaults: defaults).save(DPSelection(depth: true, pose: false))
    #expect(DPStore(defaults: defaults).load() == DPSelection(depth: true, pose: false))
  }

  @Test func anUnreadableFileMeansBoth() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("not json".utf8).write(to: folder.appendingPathComponent("state.json"))
    #expect(folderStore(folder).load() == DPSelection(depth: true, pose: true))
  }

  @Test func theOldThreeWayModeIsReadAsTwoChoices() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let expected: [String: DPSelection] = [
      "depth": .init(depth: true, pose: false), "pose": .init(depth: false, pose: true),
      "both": .init(depth: true, pose: true),
    ]
    for (mode, selection) in expected {
      try Data(#"{"mode":"\#(mode)"}"#.utf8).write(to: folder.appendingPathComponent("state.json"))
      #expect(folderStore(folder).load() == selection, "mode \(mode)")
    }
  }

  @Test func theLegacyChoiceIsAdoptedOnceAndOnlyIfThereIsNoFile() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let defaults = makeDefaults()
    DPStore(defaults: defaults).save(DPSelection(depth: true, pose: false))
    var store = DPStore(defaults: defaults)
    store.folder = folder
    store.adoptLegacy()
    #expect(store.load() == DPSelection(depth: true, pose: false))
    store.save(DPSelection(depth: false, pose: true))
    store.adoptLegacy()  // a file exists now: nothing is taken again
    #expect(store.load() == DPSelection(depth: false, pose: true))
  }
}
