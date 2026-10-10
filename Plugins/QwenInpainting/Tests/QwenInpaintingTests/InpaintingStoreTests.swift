import CoreGraphics
import Foundation
import Testing

@testable import QwenInpainting

@Suite("Inpainting store")
struct InpaintingStoreTests {
  func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("qi-store-\(UUID().uuidString)") }

  func session() -> InpaintingSession {
    var s = InpaintingSession()
    s.startImage = "/a.png"
    s.marks = [Mark(tool: .arrow, color: .green, width: 10, points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.7, y: 0.8)])]
    s.texts = ["green:arrow": "add a hat"]
    s.tool = .circle
    s.color = .blue
    s.width = 24
    s.usePE = false
    return s
  }

  @Test func theSessionRoundTrips() {
    let store = InpaintingStore(folder: folder())
    store.save(session())
    #expect(store.load() == session())
  }

  @Test func aMarkWithAnUnknownToolIsSkippedAndTheOthersStay() throws {
    let dir = folder()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let json = #"""
      {"startImage":"/a.png","marks":[
        {"tool":"box","color":"red","width":16,"points":[[0.1,0.1],[0.5,0.5]]},
        {"tool":"laser","color":"red","width":16,"points":[[0.1,0.1]]},
        {"tool":"sketch","color":"blue","width":16,"points":[[0.2,0.2]]}],
       "texts":{"red:box":"x"}}
      """#
    try Data(json.utf8).write(to: dir.appendingPathComponent("state.json"))
    let loaded = try #require(InpaintingStore(folder: dir).load())
    #expect(loaded.marks.map(\.tool) == [.box, .sketch] && loaded.texts == ["red:box": "x"])
    #expect(loaded.tool == .box && loaded.color == .red && loaded.width == 16 && loaded.usePE)  // defaults
  }

  @Test func twoProjectsAreSeparateAndABrokenFileIsNothing() throws {
    let a = InpaintingStore(folder: folder())
    let b = InpaintingStore(folder: folder())
    a.save(session())
    #expect(b.load() == nil)
    let dir = folder()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("nope".utf8).write(to: dir.appendingPathComponent("state.json"))
    #expect(InpaintingStore(folder: dir).load() == nil)
  }

  @Test func withoutAFolderItIsKeptInMemory() {
    let store = InpaintingStore(folder: nil)
    store.save(session())
    #expect(store.load() == session())
  }
}
