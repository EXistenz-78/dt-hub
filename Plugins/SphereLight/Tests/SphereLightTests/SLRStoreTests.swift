import Foundation
import SwiftUI
import Testing

@testable import SphereLight

@Suite("SLRStore and DesktopSaver")
struct SLRStoreTests {
  /// A store on a throw-away suite: never the real preferences.
  private func makeStore() -> (SLRStore, () -> Void) {
    let name = "slr-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (SLRStore(defaults: defaults), { defaults.removePersistentDomain(forName: name) })
  }

  private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("slr-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func nothingSavedMeansNoSession() {
    let (store, cleanup) = makeStore()
    defer { cleanup() }
    #expect(store.load() == nil)
  }

  @Test func threeLightsWithTheirColorsAndTheTwoBoxesComeBack() throws {
    let (store, cleanup) = makeStore()
    defer { cleanup() }
    var session = SLRSession.initial()
    session.lights.append(LightParams.makeDefault(index: 2))
    session.lights[1].color = Color(red: 1, green: 0.5, blue: 0.25)
    session.expanded[session.lights[1].id] = false
    session.overcast = true
    session.saveToDesktop = true
    store.save(session)
    let loaded = try #require(store.load())
    #expect(loaded.lights.count == 3)
    #expect(loaded.lights.map(\.id) == session.lights.map(\.id))
    #expect(loaded.lights[0].rotationDeg == -135 && loaded.lights[2].hardness == 0.3)
    #expect(loaded.expanded[session.lights[1].id] == false)
    #expect(loaded.overcast && loaded.saveToDesktop)
    let c = NSColor(loaded.lights[1].color).usingColorSpace(.deviceRGB)!
    #expect(abs(c.greenComponent - 0.5) < 0.01 && abs(c.blueComponent - 0.25) < 0.01)
  }

  @Test func theBoxesAreOffInAFirstRun() {
    let session = SLRSession.initial()
    #expect(session.lights.count == 2)
    #expect(!session.overcast && !session.saveToDesktop)
  }

  @Test func aSavedSessionWithoutLightsOrWithGarbageCountsAsNone() {
    let (store, cleanup) = makeStore()
    defer { cleanup() }
    store.defaults.set(Data("not json".utf8), forKey: store.key)
    #expect(store.load() == nil)
    store.save(SLRSession(lights: [], expanded: [:], overcast: true, saveToDesktop: true))
    #expect(store.load() == nil)
  }

  @Test func moreThanThreeSavedLightsAreCutToThree() throws {
    let (store, cleanup) = makeStore()
    defer { cleanup() }
    var session = SLRSession.initial()
    session.lights += [LightParams.makeDefault(index: 2), LightParams.makeDefault(index: 2)]
    store.save(session)
    #expect(try #require(store.load()).lights.count == 3)
  }

  @Test func theFirstSphereOfAFolderIsNumberOne() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(DesktopSaver.nextURL(in: folder).lastPathComponent == "Sphere Light 001.png")
  }

  @Test func theNextNumberIsOneMoreThanTheHighestAndOtherFilesAreIgnored() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["Sphere Light 001.png", "Sphere Light 003.png", "Sphere Light copy.png", "photo.png"] {
      try Data().write(to: folder.appendingPathComponent(name))
    }
    #expect(DesktopSaver.nextURL(in: folder).lastPathComponent == "Sphere Light 004.png")
  }

  @Test func savingTwiceMakesTwoFilesAndNeverOverwrites() throws {
    let folder = try makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = try DesktopSaver.save(Data("a".utf8), in: folder)
    let second = try DesktopSaver.save(Data("b".utf8), in: folder)
    #expect(first.lastPathComponent == "Sphere Light 001.png" && second.lastPathComponent == "Sphere Light 002.png")
    #expect(try Data(contentsOf: first) == Data("a".utf8))
  }

  @Test func aFolderThatIsNotThereIsAnError() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("slr-missing-\(UUID().uuidString)")
    #expect(throws: (any Error).self) { try DesktopSaver.save(Data("a".utf8), in: missing) }
  }
}
