import Foundation
import SwiftUI
import Testing

@testable import SphereLight

/// The state kept per project: `state.json` in the folder the app gives the plug-in for the open project.
@MainActor
@Suite("State per project")
struct SLRStoreProjectTests {
  private func defaults() -> UserDefaults { UserDefaults(suiteName: "slr-project-\(UUID().uuidString)")! }
  private func folder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("slr-project-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func session(rotation: Double, overcast: Bool = false) -> SLRSession {
    var session = SLRSession.initial()
    session.lights[0].rotationDeg = rotation
    session.overcast = overcast
    return session
  }

  private func store(_ dir: URL?, _ shared: UserDefaults? = nil) -> SLRStore {
    var store = SLRStore(defaults: shared ?? defaults())
    store.folder = dir
    return store
  }

  @Test func theStateRoundTripsThroughTheFile() throws {
    let dir = folder()
    let store = store(dir)
    store.save(session(rotation: 33, overcast: true))
    let loaded = try #require(store.load())
    #expect(loaded.lights.count == 2 && loaded.lights[0].rotationDeg == 33 && loaded.overcast)
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path))
  }

  @Test func aMissingOrCorruptFileIsNoSession() throws {
    let dir = folder()
    #expect(store(dir).load() == nil)
    try Data("not json".utf8).write(to: dir.appendingPathComponent("state.json"))
    #expect(store(dir).load() == nil)
  }

  @Test func withAFolderTheStateDoesNotGoToTheDefaults() {
    let shared = defaults()
    store(folder(), shared).save(session(rotation: 10))
    #expect(store(nil, shared).load() == nil)
  }

  @Test func withoutAFolderTheDefaultsStillWork() throws {
    let shared = defaults()
    store(nil, shared).save(session(rotation: 77))
    #expect(try #require(store(nil, shared).load()).lights[0].rotationDeg == 77)
  }

  @Test func theOldStateIsAdoptedOnlyWhenTheFileIsMissing() throws {
    let shared = defaults()
    store(nil, shared).save(session(rotation: 11))
    let dir = folder()
    let adopting = store(dir, shared)
    adopting.adoptLegacy()
    #expect(try #require(adopting.load()).lights[0].rotationDeg == 11)
    adopting.save(session(rotation: 22))
    adopting.adoptLegacy()
    #expect(try #require(adopting.load()).lights[0].rotationDeg == 22, "an existing file is never replaced")
  }

  @Test func adoptingWithoutOldStateWritesNothing() {
    let dir = folder()
    store(dir).adoptLegacy()
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path))
  }

  @Test func twoFoldersHoldTwoStates() throws {
    let (one, two) = (store(folder()), store(folder()))
    one.save(session(rotation: 1))
    two.save(session(rotation: 2))
    #expect(try #require(one.load()).lights[0].rotationDeg == 1)
    #expect(try #require(two.load()).lights[0].rotationDeg == 2)
  }

  @Test func theTabFollowsTheProject() {
    let state = SLRState(store: store(nil))
    let (a, b) = (folder(), folder())
    state.switchProject(folder: a, adoptLegacy: false)
    state.overcast = true
    state.lights[0].rotationDeg = 99
    state.switchProject(folder: b, adoptLegacy: false)
    #expect(!state.overcast)
    #expect(state.lights.count == 2 && state.lights[0].rotationDeg != 99, "a new project starts with the default lights")
    state.switchProject(folder: a, adoptLegacy: false)
    #expect(state.overcast && state.lights[0].rotationDeg == 99)
  }

  @Test func theFirstProjectTakesTheStateOfBefore() {
    let shared = defaults()
    store(nil, shared).save(session(rotation: 55, overcast: true))
    let state = SLRState(store: store(nil, shared))
    #expect(state.overcast)
    let dir = folder()
    state.switchProject(folder: dir, adoptLegacy: true)
    #expect(state.overcast && state.lights[0].rotationDeg == 55)
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path))
    state.switchProject(folder: folder(), adoptLegacy: false)
    #expect(!state.overcast)
  }

  @Test func loadingAProjectDoesNotOverwriteItsFile() throws {
    let dir = folder()
    store(dir).save(session(rotation: 44, overcast: true))
    let before = try Data(contentsOf: dir.appendingPathComponent("state.json"))
    let state = SLRState(store: store(nil))
    state.switchProject(folder: dir, adoptLegacy: false)
    #expect(state.overcast && state.lights[0].rotationDeg == 44)
    #expect(try Data(contentsOf: dir.appendingPathComponent("state.json")) == before)
  }

  @Test func theTransientStateIsNotTouched() {
    let state = SLRState(store: store(nil))
    state.status = "Sent."
    state.isSending = true
    state.switchProject(folder: folder(), adoptLegacy: false)
    #expect(state.status == "Sent." && state.isSending)
  }
}
