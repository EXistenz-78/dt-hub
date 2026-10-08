import Foundation
import Testing

@testable import HubCore

struct LegacyStateTests {
  private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private struct Setup {
    let root: URL
    let legacy: LegacyState
    let project: Project
    var oldFile: URL { root.appendingPathComponent("old/control.json") }
    var oldFolder: URL { root.appendingPathComponent("old/Control") }
  }

  private func setup(withState: Bool = true) throws -> Setup {
    let root = try makeRoot()
    let old = root.appendingPathComponent("old", isDirectory: true)
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    if withState {
      try FileManager.default.createDirectory(at: old.appendingPathComponent("Control"), withIntermediateDirectories: true)
      try Data("{\"old\":true}".utf8).write(to: old.appendingPathComponent("control.json"))
      try Data("png".utf8).write(to: old.appendingPathComponent("Control/a.png"))
    }
    let project = try ProjectCatalog(outputFolder: root.appendingPathComponent("out")).create(named: "A")
    let legacy = LegacyState(controlFile: old.appendingPathComponent("control.json"), controlFolder: old.appendingPathComponent("Control"))
    return Setup(root: root, legacy: legacy, project: project)
  }

  @Test func theOldStateMovesIntoTheProject() throws {
    let s = try setup()
    defer { try? FileManager.default.removeItem(at: s.root) }
    #expect(s.legacy.exists)
    #expect(try s.legacy.adopt(into: s.project))
    #expect(try String(contentsOf: s.project.controlFile, encoding: .utf8) == "{\"old\":true}")
    #expect(try String(contentsOf: s.project.controlFolder.appendingPathComponent("a.png"), encoding: .utf8) == "png")
    #expect(!FileManager.default.fileExists(atPath: s.oldFile.path))
    #expect(!FileManager.default.fileExists(atPath: s.oldFolder.appendingPathComponent("a.png").path))
    #expect(!s.legacy.exists)
  }

  @Test func aProjectThatAlreadyHasControlIsNotOverwritten() throws {
    let s = try setup()
    defer { try? FileManager.default.removeItem(at: s.root) }
    try Data("{\"mine\":true}".utf8).write(to: s.project.controlFile)
    #expect(try !s.legacy.adopt(into: s.project))
    #expect(try String(contentsOf: s.project.controlFile, encoding: .utf8) == "{\"mine\":true}")
    #expect(FileManager.default.fileExists(atPath: s.oldFile.path))
    #expect(FileManager.default.fileExists(atPath: s.oldFolder.appendingPathComponent("a.png").path))
  }

  @Test func withoutOldStateThereIsNothingToDo() throws {
    let s = try setup(withState: false)
    defer { try? FileManager.default.removeItem(at: s.root) }
    #expect(!s.legacy.exists)
    #expect(try !s.legacy.adopt(into: s.project))
  }

  @Test func anEmptyControlFolderIsNoState() throws {
    let s = try setup(withState: false)
    defer { try? FileManager.default.removeItem(at: s.root) }
    try FileManager.default.createDirectory(at: s.oldFolder, withIntermediateDirectories: true)
    #expect(!s.legacy.exists)
  }

  @Test func aControlFileAloneIsState() throws {
    let s = try setup(withState: false)
    defer { try? FileManager.default.removeItem(at: s.root) }
    try Data("{}".utf8).write(to: s.oldFile)
    #expect(s.legacy.exists)
    #expect(try s.legacy.adopt(into: s.project))
    #expect(FileManager.default.fileExists(atPath: s.project.controlFile.path))
  }

  @MainActor @Test func liveStateIsTheOneTheAppAlwaysUsed() {
    #expect(LegacyState.live.controlFile == ControlStore.defaultFileURL)
    #expect(LegacyState.live.controlFolder == FileReferenceStorage.defaultFolder)
  }
}
