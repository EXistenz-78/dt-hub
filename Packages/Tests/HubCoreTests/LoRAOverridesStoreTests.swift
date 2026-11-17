import HubKit
import Foundation
import Testing

@testable import HubCore

struct LoRAOverridesStoreTests {
  private func file() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("loras-\(UUID().uuidString)/loras.json")
  }

  @Test func whatWasSavedComesBack() {
    let store = LoRAOverridesStore(fileURL: file())
    var overrides = LoRAOverrides()
    overrides.entries["a.ckpt"] = LoRAOverride(trigger: "alpha", weight: 0.6)
    overrides.entries["b.ckpt"] = LoRAOverride(trigger: "", weight: nil)
    overrides.entries["c.ckpt"] = LoRAOverride(trigger: nil, weight: 2)
    store.save(overrides)
    #expect(store.load() == overrides)
  }

  @Test func anEmptyTriggerAndNoTriggerStayDifferent() {
    let store = LoRAOverridesStore(fileURL: file())
    var overrides = LoRAOverrides()
    overrides.entries["a.ckpt"] = LoRAOverride(trigger: "", weight: nil)
    overrides.entries["b.ckpt"] = LoRAOverride(trigger: nil, weight: 0.5)
    store.save(overrides)
    let loaded = store.load()
    #expect(loaded.entries["a.ckpt"]?.trigger == "")
    #expect(loaded.entries["b.ckpt"]?.trigger == nil)
  }

  @Test func aMissingFileIsAnEmptyList() {
    #expect(LoRAOverridesStore(fileURL: file()).load() == LoRAOverrides())
  }

  @Test func aCorruptFileIsAnEmptyListAndNeverACrash() throws {
    let url = file()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    #expect(LoRAOverridesStore(fileURL: url).load() == LoRAOverrides())
  }

  @Test func aFileOfAnotherLayoutIsIgnored() throws {
    let url = file()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"schema": 99, "loras": {"a.ckpt": {"trigger": "x"}}}"#.utf8).write(to: url)
    #expect(LoRAOverridesStore(fileURL: url).load() == LoRAOverrides())
  }

  @Test func aWeightOutOfRangeIsBroughtBack() throws {
    let url = file()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"schema": 1, "loras": {"a.ckpt": {"weight": 9}, "b.ckpt": {"weight": -9}}}"#.utf8).write(to: url)
    let loaded = LoRAOverridesStore(fileURL: url).load()
    #expect(loaded.entries["a.ckpt"]?.weight == 4 && loaded.entries["b.ckpt"]?.weight == -4)
  }

  @Test func theFileIsReadableByHand() throws {
    let url = file()
    let store = LoRAOverridesStore(fileURL: url)
    var overrides = LoRAOverrides()
    overrides.entries["a.ckpt"] = LoRAOverride(trigger: "alpha", weight: 0.6)
    store.save(overrides)
    let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect(object["schema"] as? Int == 1)
    let loras = try #require(object["loras"] as? [String: [String: Any]])
    #expect(loras["a.ckpt"]?["trigger"] as? String == "alpha")
    #expect(loras["a.ckpt"]?["weight"] as? Double == 0.6)
  }

  @Test func savingCreatesTheFolder() {
    let url = file()
    LoRAOverridesStore(fileURL: url).save(LoRAOverrides())
    #expect(FileManager.default.fileExists(atPath: url.path))
  }

  @Test func theDefaultFileSitsNextToTheOtherStateFiles() {
    #expect(LoRAOverridesStore.defaultFileURL.path.hasSuffix("DT Hub/loras.json"))
  }

  @Test func minAndMaxAreSavedAndBroughtIntoRange() throws {
    let url = file()
    let fox = CatalogLoRA(file: "fox.ckpt", name: "Fox", family: nil)
    var overrides = LoRAOverrides()
    overrides.setWeights(min: 0.3, base: nil, max: 1.5, for: fox)
    LoRAOverridesStore(fileURL: url).save(overrides)
    #expect(LoRAOverridesStore(fileURL: url).load().entries["fox.ckpt"]?.maxWeight == 1.5)
    try #"{"schema":1,"loras":{"a":{"minWeight":-9,"maxWeight":9}}}"#.write(to: url, atomically: true, encoding: .utf8)
    let read = LoRAOverridesStore(fileURL: url).load().entries["a"]
    #expect(read?.minWeight == -4 && read?.maxWeight == 4)
  }

  private func write(_ json: String) throws -> URL {
    let url = file()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(json.utf8).write(to: url)
    return url
  }

  @Test func newFieldsRoundTrip() {
    let store = LoRAOverridesStore(fileURL: file())
    var overrides = LoRAOverrides()
    overrides.entries["a.ckpt"] = LoRAOverride(category: "turbo", steps: 4, guidance: 1.5, shift: 3)
    store.save(overrides)
    #expect(store.load() == overrides)
  }

  @Test func anOldFileWithoutTheNewFieldsStillLoads() throws {
    let url = try write(#"{"schema": 1, "loras": {"a.ckpt": {"trigger": "x", "weight": 0.5}}}"#)
    let entry = LoRAOverridesStore(fileURL: url).load().entries["a.ckpt"]
    #expect(entry == LoRAOverride(trigger: "x", weight: 0.5))
  }

  @Test func anUnknownCategoryInTheFileIsDropped() throws {
    let url = try write(#"{"schema": 1, "loras": {"a.ckpt": {"category": "banana", "steps": 4}, "b.ckpt": {"category": "edit"}}}"#)
    let loaded = LoRAOverridesStore(fileURL: url).load()
    #expect(loaded.entries["a.ckpt"]?.category == nil && loaded.entries["a.ckpt"]?.steps == 4)
    #expect(loaded.entries["b.ckpt"]?.category == "edit")
  }

  @Test func outOfRangeNumbersInTheFileAreBroughtIn() throws {
    let url = try write(#"{"schema": 1, "loras": {"a.ckpt": {"steps": 900, "guidance": -3, "shift": 99}, "b.ckpt": {"steps": 0}}}"#)
    let loaded = LoRAOverridesStore(fileURL: url).load()
    #expect(loaded.entries["a.ckpt"]?.steps == 200 && loaded.entries["a.ckpt"]?.guidance == 0)
    #expect(loaded.entries["a.ckpt"]?.shift == 50 && loaded.entries["b.ckpt"]?.steps == 1)
  }
}
