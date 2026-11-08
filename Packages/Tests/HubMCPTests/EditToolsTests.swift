import Foundation
import MCP
import Testing

@testable import HubMCP

@MainActor
struct EditToolsTests {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("edit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data([0]).write(to: root.appendingPathComponent("ok.png"))
  }

  func harness(mode: AccessMode = .editFields) -> Harness { Harness(mode: mode, roots: [root]) }

  func text(_ r: ToolResult) -> String {
    if case .text(let t)? = r.outputs.first { return t }
    return ""
  }

  func result(_ id: String) -> AgentResult {
    AgentResult(id: id, path: "/\(id).png", prompt: "p", model: "m", date: Date(timeIntervalSince1970: 0))
  }

  @Test func setFieldsForwardsKnownKeysAndReportsApplied() async {
    let h = harness()
    let r = await h.registry.call(
      "set_fields", arguments: ["fields": .object(["prompt": .string("a cat"), "steps": .int(20), "guidanceScale": .double(3.5), "randomSeed": .bool(true)])])
    #expect(!r.isError)
    #expect(h.host.appliedFields.first?["prompt"] == .string("a cat"))
    #expect(h.host.appliedFields.first?["steps"] == .int(20))
    #expect(h.host.appliedFields.first?["guidanceScale"] == .double(3.5))
    #expect(text(r).contains("steps"))
  }

  @Test func setFieldsReportsFieldsAPluginHolds() async {
    let h = harness()
    h.host.unappliedKeys = ["steps"]
    let r = await h.registry.call("set_fields", arguments: ["fields": .object(["prompt": .string("x"), "steps": .int(9)])])
    #expect(!r.isError)
    #expect(text(r).contains("Applied: prompt.") && text(r).contains("Not applied: steps"))
  }

  @Test func setFieldsRejectsUnknownKeyListingValidOnes() async {
    let h = harness()
    let r = await h.registry.call("set_fields", arguments: ["fields": .object(["colour": .string("red")])])
    #expect(r.isError && text(r).contains("colour") && text(r).contains("guidanceScale"))
    #expect(h.host.appliedFields.isEmpty)
  }

  @Test func setFieldsRejectsWrongTypeForKey() async {
    let h = harness()
    let r = await h.registry.call("set_fields", arguments: ["fields": .object(["steps": .string("dieci")])])
    #expect(r.isError && text(r).contains("steps"))
    #expect(h.host.appliedFields.isEmpty)
  }

  @Test func setFieldsAcceptsIntegerForDoubleField() async {
    let h = harness()
    _ = await h.registry.call("set_fields", arguments: ["fields": .object(["guidanceScale": .int(4)])])
    #expect(h.host.appliedFields.first?["guidanceScale"] == .double(4))
  }

  @Test func setMoodboardResolvesResultIDsAndSaysWhenItReplaced() async {
    let h = harness()
    h.host.resultList = [result("r1"), result("r2")]
    h.host.replacedCount = 2
    let r = await h.registry.call(
      "set_moodboard",
      arguments: ["replace": .bool(true), "images": .array([.object(["result_id": .string("r1"), "weight": .double(0.8)]), .object(["result_id": .string("r2")])])])
    #expect(!r.isError)
    #expect(h.host.moodboards.first?.items == [AgentImage(.result(id: "r1"), weight: 0.8), AgentImage(.result(id: "r2"))])
    #expect(h.host.moodboards.first?.replace == true)
    #expect(text(r).contains("Replaced 2"))
  }

  @Test func setMoodboardWithUnknownResultIDIsClearError() async {
    let h = harness()
    let r = await h.registry.call("set_moodboard", arguments: ["images": .array([.object(["result_id": .string("gone")])])])
    #expect(r.isError && text(r).contains("gone"))
    #expect(h.host.moodboards.isEmpty)
  }

  @Test func setMoodboardWithPathOutsideRootsIsRefused() async {
    let h = harness()
    let r = await h.registry.call("set_moodboard", arguments: ["images": .array([.object(["path": .string("/etc/hosts.png")])])])
    #expect(r.isError && text(r).lowercased().contains("not allowed"))
    #expect(h.host.moodboards.isEmpty)
  }

  @Test func setMoodboardAcceptsAllowedPath() async {
    let h = harness()
    let path = root.appendingPathComponent("ok.png").resolvingSymlinksInPath().path
    let r = await h.registry.call("set_moodboard", arguments: ["images": .array([.object(["path": .string(path)])])])
    #expect(!r.isError)
    #expect(h.host.moodboards.first?.items == [AgentImage(.path(path))])
  }

  @Test func setStartImageResolvesResultID() async {
    let h = harness()
    h.host.resultList = [result("r1")]
    _ = await h.registry.call("set_start_image", arguments: ["result_id": .string("r1")])
    #expect(h.host.startImages == [AgentImage(.result(id: "r1"))])
  }

  @Test func addLoRAWithUnknownFileIsClearError() async {
    let h = harness()
    let r = await h.registry.call("add_lora", arguments: ["file": .string("nope.safetensors")])
    #expect(r.isError && text(r).contains("nope"))
  }

  @Test func addLoRAForwardsWeightAndDefaultsToOne() async {
    let h = harness()
    h.host.knownLoRAs = ["a.safetensors"]
    _ = await h.registry.call("add_lora", arguments: ["file": .string("a.safetensors")])
    _ = await h.registry.call("add_lora", arguments: ["file": .string("a.safetensors"), "weight": .double(0.6)])
    #expect(h.host.calls == ["addLoRA a.safetensors 1.0", "addLoRA a.safetensors 0.6"])
  }

  @Test func loraWeightOutOfRangeIsRejected() async {
    let h = harness()
    let r = await h.registry.call("set_lora_weight", arguments: ["file": .string("a"), "weight": .double(9)])
    #expect(r.isError)
  }

  @Test func setStrengthOutOfRangeIsRejected() async {
    let h = harness()
    #expect(await h.registry.call("set_strength", arguments: ["value": .double(1.5)]).isError)
    #expect(await h.registry.call("set_strength", arguments: ["value": .double(0.7)]).isError == false)
    #expect(h.host.calls == ["setStrength 0.7"])
  }

  @Test func savePresetRefusesToOverwriteAnExistingName() async {
    let h = harness()
    let r = await h.registry.call("save_preset", arguments: ["name": .string("Portrait")])
    #expect(r.isError && text(r).contains("already exists"))
    #expect(await h.registry.call("save_preset", arguments: ["name": .string("Mine")]).isError == false)
    #expect(h.host.calls == ["savePreset Mine"])
  }

  @Test func savePresetRefusesNamesTheStoreWouldTreatAsTheSame() async {
    let h = harness()
    h.host.presetList = ["Portrait", "Café"]
    for name in [" Portrait", "portrait", "PORTRAIT ", "Cafe", "café"] {
      let r = await h.registry.call("save_preset", arguments: ["name": .string(name)])
      #expect(r.isError, "\(name)")
    }
    #expect(h.host.calls.isEmpty)
    #expect(await h.registry.call("save_preset", arguments: ["name": .string("Mine")]).isError == false)
  }

  @Test func loadPresetReportsTheReasonItFailed() async {
    let h = harness()
    #expect(await h.registry.call("load_preset", arguments: ["name": .string("Portrait")]).isError == false)
  }

  @Test func editToolsAreHiddenInReadOnlyMode() {
    let h = harness(mode: .readOnly)
    let names = Set(h.registry.visibleTools().map(\.name))
    for name in ["set_fields", "add_lora", "set_moodboard", "set_start_image", "set_strength", "load_preset", "save_preset"] {
      #expect(!names.contains(name), "\(name)")
    }
  }
}
