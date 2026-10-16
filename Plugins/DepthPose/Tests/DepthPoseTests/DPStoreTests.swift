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

  @Test func theFirstRunIsBoth() {
    #expect(DPStore(defaults: makeDefaults()).load() == .both)
  }

  @Test func theModeIsKeptInTheProjectFolder() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    var store = DPStore(defaults: makeDefaults())
    store.folder = folder
    store.save(.pose)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("state.json").path))
    #expect(store.load() == .pose)
  }

  @Test func withoutAFolderItGoesToTheDefaults() {
    let defaults = makeDefaults()
    DPStore(defaults: defaults).save(.depth)
    #expect(DPStore(defaults: defaults).load() == .depth)
  }

  @Test func anUnreadableFileIsBoth() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("not json".utf8).write(to: folder.appendingPathComponent("state.json"))
    var store = DPStore(defaults: makeDefaults())
    store.folder = folder
    #expect(store.load() == .both)
  }

  @Test func theLegacyModeIsAdoptedOnceAndOnlyIfThereIsNoFile() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let defaults = makeDefaults()
    DPStore(defaults: defaults).save(.depth)
    var store = DPStore(defaults: defaults)
    store.folder = folder
    store.adoptLegacy()
    #expect(store.load() == .depth)
    store.save(.pose)
    store.adoptLegacy()  // a file exists now: nothing is taken again
    #expect(store.load() == .pose)
  }
}
