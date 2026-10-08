import Foundation
import Testing

@testable import PromptMaster

/// The state kept per project: `state.json` in the folder the app gives the plug-in for the open project.
@MainActor
@Suite("State per project")
struct PMStoreProjectTests {
  private func defaults() -> UserDefaults { UserDefaults(suiteName: "pm-project-\(UUID().uuidString)")! }
  private func folder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pm-project-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func session(_ text: String) -> PMSession {
    var session = PMSession()
    session.description = text
    session.selection = ["fr_closeup"]
    session.booru = true
    return session
  }

  @Test func theStateRoundTripsThroughTheFile() {
    let dir = folder()
    var store = PMStore(defaults: defaults())
    store.folder = dir
    store.save(session("a fox"))
    #expect(store.load() == session("a fox"))
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path))
  }

  @Test func aMissingFileIsTheInitialState() {
    var store = PMStore(defaults: defaults())
    store.folder = folder()
    #expect(store.load() == PMSession())
  }

  @Test func aCorruptFileIsTheInitialState() throws {
    let dir = folder()
    try Data("not json".utf8).write(to: dir.appendingPathComponent("state.json"))
    var store = PMStore(defaults: defaults())
    store.folder = dir
    #expect(store.load() == PMSession())
  }

  @Test func withAFolderTheStateDoesNotGoToTheDefaults() {
    let shared = defaults()
    var store = PMStore(defaults: shared)
    store.folder = folder()
    store.save(session("only in the file"))
    #expect(PMStore(defaults: shared).load() == PMSession())
  }

  @Test func withoutAFolderTheDefaultsStillWork() {
    let store = PMStore(defaults: defaults())
    store.save(session("global"))
    #expect(store.load() == session("global"))
  }

  @Test func theOldStateIsAdoptedOnlyWhenTheFileIsMissing() throws {
    let shared = defaults()
    PMStore(defaults: shared).save(session("old"))
    let dir = folder()
    var store = PMStore(defaults: shared)
    store.folder = dir
    store.adoptLegacy()
    #expect(store.load() == session("old"))
    store.save(session("new"))
    store.adoptLegacy()
    #expect(store.load() == session("new"), "an existing file is never replaced")
  }

  @Test func adoptingWithoutOldStateWritesNothing() {
    let dir = folder()
    var store = PMStore(defaults: defaults())
    store.folder = dir
    store.adoptLegacy()
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path))
  }

  @Test func twoFoldersHoldTwoStates() {
    var one = PMStore(defaults: defaults())
    var two = one
    (one.folder, two.folder) = (folder(), folder())
    one.save(session("one"))
    two.save(session("two"))
    #expect(one.load() == session("one") && two.load() == session("two"))
  }

  @Test func theTabFollowsTheProject() {
    let shared = defaults()
    let state = PMState(
      store: PMStore(defaults: shared), customStore: CustomTermsStore(folder: folder()), italian: true,
      shuffler: { _, _, _ in [] })
    let (a, b) = (folder(), folder())
    state.switchProject(folder: a, adoptLegacy: false)
    state.description = "in A"
    state.switchProject(folder: b, adoptLegacy: false)
    #expect(state.description == "")
    state.description = "in B"
    state.switchProject(folder: a, adoptLegacy: false)
    #expect(state.description == "in A")
    state.switchProject(folder: b, adoptLegacy: false)
    #expect(state.description == "in B")
  }

  @Test func theFirstProjectTakesTheStateOfBefore() {
    let shared = defaults()
    PMStore(defaults: shared).save(session("before projects"))
    let state = PMState(
      store: PMStore(defaults: shared), customStore: CustomTermsStore(folder: folder()), italian: true,
      shuffler: { _, _, _ in [] })
    #expect(state.description == "before projects")
    let dir = folder()
    state.switchProject(folder: dir, adoptLegacy: true)
    #expect(state.description == "before projects")
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path))
    // A later project does not take it.
    state.switchProject(folder: folder(), adoptLegacy: false)
    #expect(state.description == "")
  }

  @Test func loadingAProjectDoesNotOverwriteItsFileWithAHalfLoadedState() throws {
    let dir = folder()
    var seed = PMStore(defaults: defaults())
    seed.folder = dir
    seed.save(session("kept"))
    let before = try Data(contentsOf: dir.appendingPathComponent("state.json"))
    let state = PMState(
      store: PMStore(defaults: defaults()), customStore: CustomTermsStore(folder: folder()), italian: true,
      shuffler: { _, _, _ in [] })
    state.switchProject(folder: dir, adoptLegacy: false)
    #expect(state.description == "kept")
    #expect(state.booru)
    #expect(try Data(contentsOf: dir.appendingPathComponent("state.json")) == before)
  }
}
