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

  @Test func aFileFromBeforeLoadsWithTheDefaults() throws {
    let folder = Self.folder()
    try Data(
      #"{"version":1,"stickers":[{"id":"7E4B9D2A-0000-4000-8000-000000000001","name":"a.png","file":"stickers/a.png","yaw":10,"pitch":0,"rot":0,"hfov":60,"opacity":1,"visible":true}],"description":"harbour","mode":"fast","guides":false}"#
        .utf8
    ).write(to: folder.appendingPathComponent("state.json"))
    let state = PanoState.load(from: folder)
    #expect(state.stickers.count == 1 && state.description == "harbour" && state.mode == .fast && !state.guides)
    #expect(state.viewMode == .plane && state.source == .canvas && state.camera == PSCamera() && state.lastCutout == nil)
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("state.json.bak").path))
  }

  @Test func theNewFieldsRoundTrip() throws {
    let folder = Self.folder()
    var state = PanoState()
    state.viewMode = .sphere
    state.source = .result
    state.camera = PSCamera(yaw: 30, pitch: -10, fov: 70)
    state.lastCutout = PSCutoutMemory(
      yaw: 30, pitch: -10, fov: 70, width: 1152, height: 896, resultPathAtExtraction: "/r/a.png", patchPath: "/r/b.png")
    try state.save(to: folder)
    #expect(PanoState.load(from: folder) == state)
  }

  @Test func aMalformedNewFieldFallsBackAndTheRestIsKept() throws {
    let folder = Self.folder()
    try Data(
      #"{"version":1,"stickers":[],"description":"x","mode":"normal","guides":true,"camera":3,"viewMode":"weird","source":7,"cutoutMegapixels":"big","lastCutout":"no","extra":{"a":1}}"#
        .utf8
    ).write(to: folder.appendingPathComponent("state.json"))
    let state = PanoState.load(from: folder)
    #expect(state.description == "x" && state.camera == PSCamera() && state.viewMode == .plane && state.source == .canvas)
    #expect(state.lastCutout == nil)
  }

  @Test func aDamagedStickerIsStillACorruptFileNotAnEmptyOne() throws {
    let folder = Self.folder()
    try Data(#"{"version":1,"stickers":[{"name":"a"}],"description":"x","mode":"normal","guides":true}"#.utf8)
      .write(to: folder.appendingPathComponent("state.json"))
    #expect(PanoState.load(from: folder) == PanoState())
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("state.json.bak").path))
  }
}
