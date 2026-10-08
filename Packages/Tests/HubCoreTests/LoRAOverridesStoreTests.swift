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
    try Data(#"{"schema": 1, "loras": {"a.ckpt": {"weight": 7}, "b.ckpt": {"weight": -7}}}"#.utf8).write(to: url)
    let loaded = LoRAOverridesStore(fileURL: url).load()
    #expect(loaded.entries["a.ckpt"]?.weight == 2.5 && loaded.entries["b.ckpt"]?.weight == -1.5)
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
}
