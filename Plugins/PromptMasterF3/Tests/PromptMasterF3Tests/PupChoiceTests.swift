import DTHubPluginKit
import Foundation
import Testing

@testable import PromptMasterF3

struct PupChoiceTests {
  private let json = Data(#"{"t2i":"a","i2i":"b","t2i_bbox":"OFFICIAL T2I BBOX","i2i_bbox":"d"}"#.utf8)

  private func model(_ name: String, family: String?, vision: Bool = true) -> DTHubLanguageModel {
    DTHubLanguageModel(name: name, path: "/m/\(name)", supportsImages: vision, family: family, use: "both")
  }

  private func read(pups: Set<String>) -> (String) -> Data? {
    { path in pups.contains(where: { path == "/m/\($0)/system_prompts.json" }) ? self.json : nil }
  }

  @Test func pupOnTheFamilyWinsAndItsT2iBboxIsRead() {
    let mode = F3ModelChoice.mode(family: "flux3_5b", models: [model("pup", family: "flux3_5b"), model("qwen", family: "*")], readFile: read(pups: ["pup"]))
    #expect(mode == .pup(name: "pup", systemPrompt: "OFFICIAL T2I BBOX"))
  }

  @Test func pupOnAllOthersWhenNoModelHasTheFamily() {
    #expect(F3ModelChoice.mode(family: "flux3_5b", models: [model("pup", family: "*")], readFile: read(pups: ["pup"])) == .pup(name: "pup", systemPrompt: "OFFICIAL T2I BBOX"))
  }

  @Test func theFamilyModelBeatsAllOthersAndCarriesItsNameWhenItIsNotAPup() {
    let mode = F3ModelChoice.mode(family: "flux3_5b", models: [model("pup", family: "*"), model("qwen", family: "flux3_5b")], readFile: read(pups: ["pup"]))
    #expect(mode == .standard(model: "qwen"))
  }

  @Test func aModelOfAnotherFamilyOrWithoutVisionOrTheKeyIsNotUsedAsPup() {
    #expect(F3ModelChoice.mode(family: "flux3_5b", models: [model("pup", family: "other")], readFile: read(pups: ["pup"])) == .standard(model: nil))
    #expect(F3ModelChoice.mode(family: "flux3_5b", models: [model("pup", family: "flux3_5b", vision: false)], readFile: read(pups: ["pup"])) == .standard(model: "pup"))
    #expect(F3ModelChoice.mode(family: "flux3_5b", models: [model("x", family: "flux3_5b")], readFile: { _ in Data(#"{"t2i":"a"}"#.utf8) }) == .standard(model: "x"))
    #expect(F3ModelChoice.mode(family: "flux3_5b", models: [], readFile: { _ in nil }) == .standard(model: nil))
  }

  @Test func requestHasTheOfficialShapeAndOptions() {
    let rows = [PupRow(id: "lamp_1", bbox: [1, 2, 30, 40], desc: "A lamp")]
    let message = F3PupRequest.message(prose: "A room with <lamp_1>.", locked: rows)
    #expect(message == "ORIGINAL PROMPT:\nA room with <lamp_1>.\n\nLOCKED BOUNDING-BOX ANNOTATIONS ([y_min, x_min, y_max, x_max] on a 0-1000 canvas, with (0, 0) at the top-left). This is an authoritative JSON list of dictionaries; preserve every supplied identity, provenance value, null, and coordinate exactly:\n" + PupRecord.json(rows))
    #expect(F3PupRequest.message(prose: "p", locked: [], reminder: "REMIND").hasSuffix("\nREMIND"))
    let o = F3PupRequest.options
    #expect(o.temperature == 0 && o.topP == 0.95 && o.topK == 20 && o.presencePenalty == 1.5 && o.maxTokens == 3584 && o.thinking == false)
  }
}
