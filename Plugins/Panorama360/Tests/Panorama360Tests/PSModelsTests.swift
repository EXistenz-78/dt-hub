import Foundation
import Testing

@testable import Panorama360

@Suite("Model")
struct PSModelsTests {
  static func folder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("p360-\(UUID())", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func roundTripKeepsEverythingInOrder() throws {
    let folder = Self.folder()
    var state = PanoState()
    state.stickers = [
      Sticker(name: "a.png", file: "stickers/a.png", yaw: -35, pitch: 4, rot: 8, hfov: 70, opacity: 0.5, visible: false),
      Sticker(name: "b.png", file: "stickers/b.png"),
    ]
    state.selectedID = state.stickers[1].id
    state.description = "Mountain valley at sunset"
    state.mode = .fast
    state.guides = false
    try state.save(to: folder)
    #expect(PanoState.load(from: folder) == state)
  }

  @Test func aMissingFileIsAnEmptyState() {
    #expect(PanoState.load(from: Self.folder()) == PanoState())
  }

  @Test func corruptFileStartsEmptyAndKeepsBackup() throws {
    let folder = Self.folder()
    try Data("{ not json".utf8).write(to: folder.appendingPathComponent("state.json"))
    #expect(PanoState.load(from: folder) == PanoState())
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("state.json").path))
    #expect(try Data(contentsOf: folder.appendingPathComponent("state.json.bak")) == Data("{ not json".utf8))
  }

  @Test func newerVersionIsTreatedAsCorrupt() throws {
    let folder = Self.folder()
    try Data(#"{"version":2,"stickers":[],"description":"x","mode":"normal","guides":true}"#.utf8)
      .write(to: folder.appendingPathComponent("state.json"))
    #expect(PanoState.load(from: folder) == PanoState())
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("state.json.bak").path))
  }

  @Test func aSecondBackupReplacesTheFirst() throws {
    let folder = Self.folder()
    try Data("one".utf8).write(to: folder.appendingPathComponent("state.json"))
    _ = PanoState.load(from: folder)
    try Data("two".utf8).write(to: folder.appendingPathComponent("state.json"))
    _ = PanoState.load(from: folder)
    #expect(try Data(contentsOf: folder.appendingPathComponent("state.json.bak")) == Data("two".utf8))
  }
}
