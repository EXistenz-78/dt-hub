import Foundation
import HubKit
import Testing

@testable import HubCore

struct UserPipelineTests {
  func read(_ json: String) -> UserPipeline? { UserPipeline(data: Data(json.utf8)) }

  @Test func readsTheSpecExample() throws {
    let pipeline = try #require(
      read(
        """
        {"chain": true, "steps": [
          {"preset": null},
          {"preset": "Qwen · Upscale", "scale": 2},
          {"preset": "SD 1.5 · Rifinitura", "scale": 1, "strength": 0.3}
        ]}
        """))
    #expect(pipeline.chain)
    #expect(
      pipeline.steps == [
        .init(preset: nil), .init(preset: "Qwen · Upscale", scale: 2),
        .init(preset: "SD 1.5 · Rifinitura", scale: 1, strength: 0.3),
      ])
  }

  @Test func valuesComeBackWithinTheirLimits() throws {
    func step(_ body: String) throws -> UserPipeline.Step {
      try #require(read(#"{"steps":[{"preset":"A",\#(body)}]}"#)).steps[0]
    }
    #expect(try step(#""scale":0"#).scale == 0.25)
    #expect(try step(#""scale":100"#).scale == 4)
    #expect(try step(#""scale":"big""#).scale == 1)
    #expect(try step(#""scale":1.5"#).scale == 1.5)
    #expect(try step(#""strength":5"#).strength == 1)
    #expect(try step(#""strength":-1"#).strength == 0)
    #expect(try step(#""strength":"x""#).strength == nil)
  }

  @Test func anUnreadableStepIsSkipped() throws {
    let pipeline = try #require(read(#"{"steps":[{"preset":null}, 7, {"preset":""}, {"scale":2}, {"preset":" A "}]}"#))
    #expect(pipeline.steps.map(\.preset) == [nil, "A"])
  }

  @Test func aFileWithoutStepsIsNotAPipeline() {
    #expect(read(#"{"chain":true,"steps":[]}"#) == nil)
    #expect(read(#"{"steps":3}"#) == nil)
    #expect(read("[]") == nil)
    #expect(read("x") == nil)
    #expect(read(#"{"steps":[7]}"#) == nil)
  }

  @Test func aMissingChainIsOn() throws {
    #expect(try #require(read(#"{"steps":[{"preset":null},{"preset":"A"}]}"#)).chain)
    #expect(try #require(read(#"{"chain":false,"steps":[{"preset":null}]}"#)).chain == false)
  }

  @Test func writesAndReadsBack() throws {
    let pipeline = UserPipeline(
      chain: false, steps: [.init(preset: nil), .init(preset: "A", scale: 2), .init(preset: "B", strength: 0.3)])
    let data = pipeline.data()
    #expect(UserPipeline(data: data) == pipeline)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.contains(#""preset" : null"#))
  }

  @Test func theNamesOfThePresetsAreListedOnce() {
    let pipeline = UserPipeline(steps: [.init(preset: "B"), .init(preset: nil), .init(preset: "A"), .init(preset: "B")])
    #expect(pipeline.presetNames == ["B", "A"])
  }
}

@MainActor
struct UserPipelineStoreTests {
  func tempFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("UserPipelineStoreTests-\(UUID())", isDirectory: true)
  }

  func files(_ folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
  }

  let two = UserPipeline(steps: [.init(preset: nil), .init(preset: "A", scale: 2)])

  @Test func savesAndLoads() throws {
    let folder = tempFolder()
    let store = UserPipelineStore(folder: folder)
    #expect(store.names.isEmpty)
    try store.save(two, named: "Zeta")
    try store.save(two, named: "alpha")
    #expect(files(folder) == ["Zeta.json", "alpha.json"])
    #expect(store.names == ["alpha", "Zeta"])
    #expect(try UserPipelineStore(folder: folder).load(named: "Zeta") == two)
  }

  @Test func invalidNamesAreRefused() {
    let folder = tempFolder()
    let store = UserPipelineStore(folder: folder)
    for name in ["", "a/b", "a:b", ".x"] {
      #expect(throws: PresetError.invalidName) { try store.save(two, named: name) }
    }
    #expect(files(folder).isEmpty)
  }

  @Test func savingAnExistingNameReplacesIt() throws {
    let folder = tempFolder()
    let store = UserPipelineStore(folder: folder)
    try store.save(two, named: "Fast")
    let three = UserPipeline(steps: two.steps + [.init(preset: "B")])
    try store.save(three, named: "fast")
    #expect(files(folder) == ["Fast.json"])
    #expect(try store.load(named: "Fast") == three)
  }

  @Test func renamingToATakenNameIsRefused() throws {
    let store = UserPipelineStore(folder: tempFolder())
    try store.save(two, named: "A")
    try store.save(two, named: "B")
    #expect(throws: PresetError.nameTaken) { try store.rename("A", to: "b") }
    try store.rename("A", to: "C")
    #expect(store.names == ["B", "C"])
  }

  @Test func capitalsAndAccentsDoNotTellNamesApart() throws {
    let store = UserPipelineStore(folder: tempFolder())
    try store.save(two, named: "Più")
    #expect(store.existingName(for: "PIU") == "Più")
    #expect(store.contains("piu"))
  }

  @Test func anUnreadableFileIsListedAndFailsOnLoad() throws {
    let folder = tempFolder()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: folder.appendingPathComponent("Rotto.json"))
    let store = UserPipelineStore(folder: folder)
    #expect(store.names == ["Rotto"])
    #expect(throws: PresetError.unreadable("Rotto")) { try store.load(named: "Rotto") }
  }

  @Test func loadOfAMissingNameIsNotFound() {
    let store = UserPipelineStore(folder: tempFolder())
    #expect(throws: PresetError.notFound("No")) { try store.load(named: "No") }
  }

  @Test func deleteRemovesTheFile() throws {
    let folder = tempFolder()
    let store = UserPipelineStore(folder: folder)
    try store.save(two, named: "A")
    store.delete(named: "a")
    #expect(store.names.isEmpty && files(folder).isEmpty)
  }

  @Test func renamePresetTouchesOnlyThePipelinesThatNameIt() throws {
    let folder = tempFolder()
    let store = UserPipelineStore(folder: folder)
    try store.save(
      UserPipeline(steps: [.init(preset: "Flux"), .init(preset: "Qwen", scale: 2, strength: 0.3)]), named: "A")
    try store.save(UserPipeline(steps: [.init(preset: nil), .init(preset: "Altro")]), named: "B")
    try Data("x".utf8).write(to: folder.appendingPathComponent("Rotto.json"))
    let other = folder.appendingPathComponent("B.json")
    // An odd layout tells a rewritten file from one left alone.
    try Data(#"{"steps":[{"preset":null},{"preset":"Altro"}]}"#.utf8).write(to: other)
    let before = try Data(contentsOf: other)
    store.renamePreset("flux", to: "Flux 2")
    #expect(
      try store.load(named: "A")
        == UserPipeline(steps: [.init(preset: "Flux 2"), .init(preset: "Qwen", scale: 2, strength: 0.3)]))
    #expect(try Data(contentsOf: other) == before)
    #expect(try Data(contentsOf: folder.appendingPathComponent("Rotto.json")) == Data("x".utf8))
  }
}
