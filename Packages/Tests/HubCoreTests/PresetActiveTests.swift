import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct PresetActiveTests {
  private func store(with names: [String]) throws -> PresetStore {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PresetActive-\(UUID())", isDirectory: true)
    let store = PresetStore(folder: folder)
    for name in names { try store.save(Preset(name: name)) }
    return store
  }

  @Test func nothingIsActiveUntilAPresetIsLoaded() throws {
    #expect(try store(with: ["A"]).activeName == nil)
  }

  @Test func theLoadedPresetIsTheActiveOneUnderTheNameOfItsFile() throws {
    let s = try store(with: ["Sphere Light"])
    s.markLoaded("sphere light")
    #expect(s.activeName == "Sphere Light", "the name is the file's, not the one that was asked for")
  }

  @Test func aDeletedPresetIsNoLongerActive() throws {
    let s = try store(with: ["A", "B"])
    s.markLoaded("A")
    s.delete(named: "A")
    #expect(s.activeName == nil)
  }

  @Test func aRenamedPresetStaysActiveUnderItsNewName() throws {
    let s = try store(with: ["A"])
    s.markLoaded("A")
    try s.rename("A", to: "C")
    #expect(s.activeName == "C")
  }

  @Test func savingUnderANameMakesItTheActiveOne() throws {
    let s = try store(with: ["A"])
    s.markLoaded("A")
    try s.save(Preset(name: "New"))
    #expect(s.activeName == "A", "saving does not change it by itself: the caller says so")
    s.markLoaded("New")
    #expect(s.activeName == "New")
  }

  @Test func renamingAnotherPresetLeavesTheActiveOneAlone() throws {
    let s = try store(with: ["A", "B"])
    s.markLoaded("A")
    try s.rename("B", to: "C")
    #expect(s.activeName == "A")
  }
}
