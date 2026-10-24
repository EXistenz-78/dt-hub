import DTHubPluginKit
import Foundation
import Testing

@testable import Flux3Editing

struct ModelChoiceTests {
  private let pupJSON = Data(#"{"t2i":"a","i2i":"b","t2i_bbox":"c","i2i_bbox":"OFFICIAL"}"#.utf8)

  private func model(_ name: String, family: String?, vision: Bool = true) -> DTHubLanguageModel {
    DTHubLanguageModel(name: name, path: "/m/\(name)", supportsImages: vision, family: family, use: "both")
  }

  /// Il `system_prompts.json` esiste solo nelle cartelle dei modelli `pups`.
  private func read(pups: Set<String>) -> (String) -> Data? {
    { path in pups.contains(where: { path == "/m/\($0)/system_prompts.json" }) ? self.pupJSON : nil }
  }

  @Test func pupAssignedToTheFamilyWins() {
    let mode = EditModelChoice.mode(family: "flux3_5b", models: [model("pup", family: "flux3_5b"), model("qwen", family: "*")], readFile: read(pups: ["pup"]))
    #expect(mode == .pup(name: "pup", systemPrompt: "OFFICIAL"))
  }

  @Test func pupOnAllOthersWhenNoModelHasTheFamily() {
    let mode = EditModelChoice.mode(family: "flux3_5b", models: [model("pup", family: "*")], readFile: read(pups: ["pup"]))
    #expect(mode == .pup(name: "pup", systemPrompt: "OFFICIAL"))
  }

  @Test func aModelOfAnotherFamilyIsIgnored() {
    let mode = EditModelChoice.mode(family: "flux3_5b", models: [model("pup", family: "qwen_image_2.1")], readFile: read(pups: ["pup"]))
    #expect(mode == .standard(model: nil))
  }

  @Test func theFamilyModelBeatsAllOthers() {
    let qwenOnFamily = EditModelChoice.mode(
      family: "flux3_5b", models: [model("pup", family: "*"), model("qwen", family: "flux3_5b")], readFile: read(pups: ["pup"]))
    #expect(qwenOnFamily == .standard(model: "qwen"))
  }

  @Test func firstByNameAmongSeveral() {
    let mode = EditModelChoice.mode(
      family: "flux3_5b", models: [model("pup-b", family: "flux3_5b"), model("pup-a", family: "flux3_5b")], readFile: read(pups: ["pup-a", "pup-b"]))
    #expect(mode == .pup(name: "pup-a", systemPrompt: "OFFICIAL"))
  }

  @Test func aFolderWithoutI2iBboxIsStandard() {
    let readNoKey: (String) -> Data? = { _ in Data(#"{"t2i":"a"}"#.utf8) }
    #expect(EditModelChoice.mode(family: "flux3_5b", models: [model("x", family: "flux3_5b")], readFile: readNoKey) == .standard(model: "x"))
    #expect(EditModelChoice.mode(family: "flux3_5b", models: [model("x", family: "flux3_5b")], readFile: { _ in nil }) == .standard(model: "x"))
  }

  @Test func aPupWithoutVisionIsStandard() {
    let mode = EditModelChoice.mode(family: "flux3_5b", models: [model("pup", family: "flux3_5b", vision: false)], readFile: read(pups: ["pup"]))
    #expect(mode == .standard(model: "pup"))  // the model is the chosen one even if it cannot be used as a PUP
  }

  @Test func noLanguageModelsMeansStandard() {
    #expect(EditModelChoice.mode(family: "flux3_5b", models: [], readFile: { _ in nil }) == .standard(model: nil))
  }

  @Test func withoutAFamilyOnlyAllOthersCount() {
    let mode = EditModelChoice.mode(family: nil, models: [model("pup", family: "flux3_5b")], readFile: read(pups: ["pup"]))
    #expect(mode == .standard(model: nil))
  }

  @MainActor @Test func theStateKeepsTheModelsAndTheFamilyOfTheContext() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-pup-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try pupJSON.write(to: folder.appendingPathComponent("system_prompts.json"))
    let s = EditState(store: EditStore(storage: MemoryStorage()), italian: false)
    let json = #"{"type":"context","tempFolder":"/tmp","family":"flux3_5b","languageModels":[{"name":"pup","path":"\#(folder.path)","supportsImages":true,"family":"flux3_5b","use":"both"}]}"#
    s.update(context: try JSONDecoder().decode(DTHubContext.self, from: Data(json.utf8)))
    #expect(s.writeMode == .pup(name: "pup", systemPrompt: "OFFICIAL"))
    s.update(context: try JSONDecoder().decode(DTHubContext.self, from: Data(#"{"type":"context","tempFolder":"/tmp"}"#.utf8)))
    #expect(s.writeMode == .standard(model: nil))
  }
}
