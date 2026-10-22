import AppKit
import Foundation
import Testing

@testable import Flux3Editing

final class MemoryStorage: EditStorage, @unchecked Sendable {
  var values: [String: Data] = [:]
  func data(forKey key: String) -> Data? { values[key] }
  func set(_ data: Data, forKey key: String) { values[key] = data }
}

struct StoreTests {
  @Test func aSessionIsSavedAndLoadedBack() {
    let store = EditStore(storage: MemoryStorage())
    var session = EditSession()
    session.document.prose = "Modify <ref_image_0>"
    session.document.draw(onCanvas: BBox(y0: 10, x0: 20, y1: 300, x1: 400))
    store.save(session)
    #expect(store.load() == session)
  }

  @Test func aSessionOfAnotherLayoutOrBrokenBytesStartsEmpty() {
    let storage = MemoryStorage()
    let store = EditStore(storage: storage)
    storage.set(Data("nonsense".utf8), forKey: EditStore.key)
    #expect(store.load() == EditSession())
    var other = EditSession()
    other.schema = 99
    other.document.prose = "x"
    store.save(other)
    #expect(store.load() == EditSession())
  }

  @Test func theFirstProjectAdoptsTheSessionTheTabHadBefore() {
    let legacy = MemoryStorage(), fresh = MemoryStorage()
    var session = EditSession()
    session.document.prose = "old"
    EditStore(storage: legacy).save(session)
    let store = EditStore(storage: fresh)
    store.adoptLegacy(from: legacy)
    #expect(store.load().document.prose == "old")
    // A session that exists is not overwritten.
    var newer = EditSession()
    newer.document.prose = "newer"
    store.save(newer)
    store.adoptLegacy(from: legacy)
    #expect(store.load().document.prose == "newer")
  }

  @Test func fileStorageKeepsOneStateFileInTheProjectFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = EditStore(storage: FileStorage(folder: folder))
    var session = EditSession()
    session.document.prose = "in a file"
    store.save(session)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("state.json").path))
    #expect(store.load().document.prose == "in a file")
  }

  @Test func theWorkFolderKeepsTheLastWriteInThreeFiles() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let before = EditSnapshot(prose: "p", descriptions: ["a": "d"])
    EditWorkFolder(folder: folder).write(request: "REQ", answer: "ANS", before: before)
    let dir = folder.appendingPathComponent("llm")
    #expect(try String(contentsOf: dir.appendingPathComponent("request.md"), encoding: .utf8) == "REQ")
    #expect(try String(contentsOf: dir.appendingPathComponent("answer.md"), encoding: .utf8) == "ANS")
    #expect(try String(contentsOf: dir.appendingPathComponent("before.md"), encoding: .utf8).contains("## element: a\nd"))
  }

  @Test func imageSizeIsReadFromTheFileWithoutLoadingIt() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    let rep = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 30, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    #expect(ImageSizes.read(path: url.path) == CGSize(width: 30, height: 20))
    #expect(ImageSizes.read(path: "/nonexistent.png") == nil)
  }
}
