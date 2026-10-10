import Foundation
import Testing

@testable import BatchPlus

@Suite("State per project")
struct BatchPlusStoreTests {
  private func defaults() -> UserDefaults { UserDefaults(suiteName: "bp-\(UUID().uuidString)")! }
  private func folder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("bp-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  private func store(_ dir: URL?, _ shared: UserDefaults? = nil) -> BatchPlusStore {
    var store = BatchPlusStore(defaults: shared ?? defaults())
    store.folder = dir
    return store
  }

  private func edited() -> BatchPlusSession {
    var s = BatchPlusSession.initial()
    s.mode = .prompts
    s.increments = ["steps": "10", "lora:x.ckpt": "0,2"]
    s.count = 7
    s.fixedSeed = false
    s.promptText = "<a|b>"
    s.shuffle = true
    return s
  }

  @Test func theSessionRoundTripsThroughTheFile() throws {
    let dir = folder()
    let store = store(dir)
    store.save(edited())
    #expect(try #require(store.load()) == edited())
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json").path))
  }

  @Test func aMissingOrBrokenFileIsNoSession() throws {
    let dir = folder()
    #expect(store(dir).load() == nil)
    try Data("garbage".utf8).write(to: dir.appendingPathComponent("state.json"))
    #expect(store(dir).load() == nil)
  }

  @Test func theInitialSessionIsParametersThreePassesFixedSeed() {
    let s = BatchPlusSession.initial()
    #expect(s.mode == .parameters && s.count == 3 && s.fixedSeed && s.increments.isEmpty && s.promptText.isEmpty)
  }

  @Test func twoProjectsAreIndependent() {
    let a = store(folder())
    let b = store(folder())
    a.save(edited())
    #expect(b.load() == nil)
  }

  @Test func beforeTheFirstProjectTheDefaultsHoldTheStateAndTheFirstProjectAdoptsIt() {
    let shared = defaults()
    store(nil, shared).save(edited())
    let dir = folder()
    let withFolder = store(dir, shared)
    #expect(withFolder.load() == nil)
    withFolder.adoptLegacy()
    #expect(withFolder.load() == edited())
    // A project that already has its state keeps it.
    let other = store(folder(), shared)
    var mine = BatchPlusSession.initial()
    mine.count = 4
    other.save(mine)
    other.adoptLegacy()
    #expect(other.load()?.count == 4)
  }

  @Test func aSavedNumberOfPassesOutOfRangeIsBroughtBack() {
    let s = store(folder())
    var big = BatchPlusSession.initial()
    big.count = 500
    s.save(big)
    #expect(s.load()?.count == 50)
  }

  @Test func theIncrementsBecomeABatchAndShiftIsIgnoredWithAuto() {
    var s = BatchPlusSession.initial()
    s.increments = ["steps": "10", "shift": "0,5", "lora:x.ckpt": "-0,1", "seed": "1.5", "guidanceScale": ""]
    let manual = s.batch(shiftIsAuto: false)
    #expect(manual.batch.increments == [.steps: 10, .shift: 0.5])
    #expect(manual.batch.loraIncrements == ["x.ckpt": -0.1])
    #expect(manual.invalid == ["seed"])
    #expect(s.batch(shiftIsAuto: true).batch.increments == [.steps: 10])
  }

  @Test func chosenSamplersAreSavedAndAnOldStateWithoutThemStillLoads() throws {
    let s = store(folder())
    var session = BatchPlusSession.initial()
    session.samplers = [5, 2]
    s.save(session)
    #expect(s.load()?.samplers == [5, 2])
    let old = Data(#"{"mode":"parameters","increments":{},"count":4,"fixedSeed":true,"promptText":""}"#.utf8)
    let loaded = try JSONDecoder().decode(BatchPlusSession.self, from: old)
    #expect(loaded.samplers.isEmpty && loaded.count == 4)
  }

  @Test func neverMoreSamplersThanPasses() {
    var session = BatchPlusSession.initial()
    session.count = 4
    session.samplers = [1, 2, 3, 4]
    session.count = 2
    session.trimSamplers()
    #expect(session.samplers == [1, 2])
    #expect(session.batch(shiftIsAuto: false).batch.samplers == [1, 2])
  }
}
