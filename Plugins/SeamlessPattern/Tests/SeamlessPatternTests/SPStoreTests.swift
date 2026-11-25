import Foundation
import Testing

@testable import SeamlessPattern

@Suite("SPStore")
struct SPStoreTests {
  private func folder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("sp-store-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func savedStateIsReadBackWithModeAndView() {
    let dir = folder()
    var store = SPStore()
    store.folder = dir
    store.save(SPSession(mode: .leftRight, view: .halfBrick))
    #expect(store.load() == SPSession(mode: .leftRight, view: .halfBrick))
  }

  @Test func eachProjectKeepsItsOwnState() {
    let (a, b) = (folder(), folder())
    var store = SPStore()
    store.folder = a
    store.save(SPSession(mode: .upDown, view: .offset))
    store.folder = b
    #expect(store.load() == nil)
    store.save(SPSession(mode: .both, view: .twoByTwo))
    store.folder = a
    #expect(store.load() == SPSession(mode: .upDown, view: .offset))
  }

  @Test func nothingOrGarbageIsNil() throws {
    let dir = folder()
    var store = SPStore()
    #expect(store.load() == nil)
    store.folder = dir
    #expect(store.load() == nil)
    try Data("nope".utf8).write(to: dir.appendingPathComponent(SPStore.fileName))
    #expect(store.load() == nil)
  }
}
