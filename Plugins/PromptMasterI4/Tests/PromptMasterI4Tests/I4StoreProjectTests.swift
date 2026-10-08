import Foundation
import Testing

@testable import PromptMasterI4

/// The state kept per project: `state.json` in the folder the app gives the plug-in for the open project.
@MainActor
@Suite("State per project")
struct I4StoreProjectTests {
  private func folder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("i4-project-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func session(_ text: String) -> I4Session {
    var session = I4Session()
    session.document.description = text
    session.openSections = ["A"]
    return session
  }

  private func state(_ storage: any I4Storage = MemoryStorage()) -> I4State {
    I4State(
      data: I4Data(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig, warnings: []),
      store: I4Store(storage: storage), italian: false)
  }

  @Test func theStateRoundTripsThroughTheFile() {
    let dir = folder()
    let store = I4Store(storage: FileStorage(folder: dir))
    store.save(session("a poster"))
    #expect(store.load() == session("a poster"))
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path))
  }

  @Test func aMissingFileIsTheInitialState() {
    #expect(I4Store(storage: FileStorage(folder: folder())).load() == I4Session())
  }

  @Test func aCorruptFileIsTheInitialState() throws {
    let dir = folder()
    try Data("not json".utf8).write(to: dir.appendingPathComponent("state.json"))
    #expect(I4Store(storage: FileStorage(folder: dir)).load() == I4Session())
  }

  @Test func aFileOfAnotherLayoutIsTheInitialState() throws {
    let dir = folder()
    var other = session("from the future")
    other.schema = I4Session.currentSchema + 1
    try JSONEncoder().encode(other).write(to: dir.appendingPathComponent("state.json"))
    #expect(I4Store(storage: FileStorage(folder: dir)).load() == I4Session())
  }

  @Test func twoFoldersHoldTwoStates() {
    let (one, two) = (I4Store(storage: FileStorage(folder: folder())), I4Store(storage: FileStorage(folder: folder())))
    one.save(session("one"))
    two.save(session("two"))
    #expect(one.load() == session("one") && two.load() == session("two"))
  }

  @Test func theOldStateIsAdoptedOnlyWhenTheFileIsMissing() {
    let old = MemoryStorage()
    I4Store(storage: old).save(session("old"))
    let store = I4Store(storage: FileStorage(folder: folder()))
    store.adoptLegacy(from: old)
    #expect(store.load() == session("old"))
    store.save(session("new"))
    store.adoptLegacy(from: old)
    #expect(store.load() == session("new"), "an existing file is never replaced")
  }

  @Test func adoptingWithoutOldStateWritesNothing() {
    let dir = folder()
    I4Store(storage: FileStorage(folder: dir)).adoptLegacy(from: MemoryStorage())
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path))
  }

  @Test func theTabFollowsTheProject() {
    let state = state()
    let (a, b) = (folder(), folder())
    state.switchProject(folder: a, adoptLegacy: false)
    state.document.description = "in A"
    state.switchProject(folder: b, adoptLegacy: false)
    #expect(state.document.description == "")
    state.document.description = "in B"
    state.switchProject(folder: a, adoptLegacy: false)
    #expect(state.document.description == "in A")
  }

  @Test func theFirstProjectTakesTheStateOfBefore() {
    let old = MemoryStorage()
    I4Store(storage: old).save(session("before projects"))
    let state = state(old)
    #expect(state.document.description == "before projects")
    let dir = folder()
    state.switchProject(folder: dir, adoptLegacy: true)
    #expect(state.document.description == "before projects")
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path))
    state.switchProject(folder: folder(), adoptLegacy: false)
    #expect(state.document.description == "")
  }

  @Test func loadingAProjectDoesNotOverwriteItsFile() throws {
    let dir = folder()
    I4Store(storage: FileStorage(folder: dir)).save(session("kept"))
    let before = try Data(contentsOf: dir.appendingPathComponent("state.json"))
    let state = state()
    state.switchProject(folder: dir, adoptLegacy: false)
    #expect(state.document.description == "kept")
    #expect(state.openSections == ["A"])
    #expect(try Data(contentsOf: dir.appendingPathComponent("state.json")) == before)
  }
}
