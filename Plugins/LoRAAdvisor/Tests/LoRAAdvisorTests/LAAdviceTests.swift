import Foundation
import DTHubPluginKit
import Testing

@testable import LoRAAdvisor

struct LAAdviceTests {
  func lora(_ name: String, family: String? = "flux2_9b", trigger: String = "", weight: Double = 1) -> DTHubCatalogLoRA {
    DTHubCatalogLoRA(file: name.lowercased() + ".ckpt", name: name, family: family, trigger: trigger, weight: weight)
  }

  var three: [LAAdvice.Candidate] {
    [lora("A", weight: 0.8), lora("B"), lora("C", trigger: "cc")].map { LAAdvice.Candidate(lora: $0, notes: "") }
  }

  @Test func onlyTheCurrentFamilyIsACandidate() {
    let catalog = [lora("A"), lora("Q", family: "qwen_image_2.1"), lora("U", family: nil), lora("B")]
    #expect(LAAdvice.candidates(catalog: catalog, family: "flux2_9b", notes: [:], request: "x").map(\.lora.name) == ["A", "B"])
    #expect(LAAdvice.candidates(catalog: catalog, family: nil, notes: [:], request: "x").isEmpty)
  }

  @Test func theNotesGoWithTheCandidates() {
    let found = LAAdvice.candidates(catalog: [lora("A")], family: "flux2_9b", notes: ["a.ckpt": "grana"], request: "x")
    #expect(found == [LAAdvice.Candidate(lora: lora("A"), notes: "grana")])
  }

  @Test func beyondTheLimitTheClosestToTheRequestStay() {
    let catalog = (1...50).map { lora("L\($0)") }
    let notes = ["l7.ckpt": "grana da film", "l33.ckpt": "Film 35mm", "l49.ckpt": "pellicola"]
    let kept = LAAdvice.candidates(catalog: catalog, family: "flux2_9b", notes: notes, request: "pellicola film 35mm", limit: 40)
    #expect(kept.count == 40)
    #expect(Set(["L7", "L33", "L49"]).isSubset(of: Set(kept.map(\.lora.name))))
    #expect(kept.map(\.lora.name) == catalog.map(\.name).filter { kept.map(\.lora.name).contains($0) })
    // Short of a word in common, the LoRAs with notes come before those without.
    let withNotes = LAAdvice.candidates(catalog: catalog, family: "flux2_9b", notes: ["l50.ckpt": "altro"], request: "zzz", limit: 2)
    #expect(withNotes.map(\.lora.name) == ["L1", "L50"])
  }

  @Test func theLinesOfThePrompt() {
    let candidates = [
      LAAdvice.Candidate(lora: lora("A"), notes: "riga 1\nriga 2"),
      LAAdvice.Candidate(lora: lora("B", trigger: "bb"), notes: String(repeating: "x", count: 500)),
      LAAdvice.Candidate(lora: lora("C"), notes: ""),
    ]
    let prompt = LAAdvice.prompt(request: "un ritratto", guide: "FLUX.2", candidates: candidates)
    #expect(prompt.contains("1. A | - | riga 1 riga 2\n"))
    #expect(prompt.contains("2. B | bb | " + String(repeating: "x", count: 300) + "\n"))
    #expect(prompt.contains("3. C | - | -"))
    #expect(prompt.contains("un ritratto") && prompt.contains("FLUX.2"))
    #expect(LAAdvice.system(italian: true, folder: tempPrompts()).contains("JSON")
        && LAAdvice.system(italian: true, folder: tempPrompts()).contains("italiano"))
  }

  @Test func aListIsReadWhateverIsAroundIt() {
    #expect(
      LAAdvice.parse(#"Ecco: [{"n":2,"weight":0.8,"why":"x"}] fine"#, candidates: three)
        == [LAAdvice.Suggestion(file: "b.ckpt", weight: 0.8, why: "x")])
    #expect(LAAdvice.parse("```json\n[{\"n\": 3, \"why\": \"y\"}]\n```", candidates: three) == [LAAdvice.Suggestion(file: "c.ckpt", weight: 1, why: "y")])
  }

  @Test func wrongNumbersAndRepeatsAreDropped() {
    #expect(
      LAAdvice.parse(#"[{"n":9},{"n":0},{"n":"2"},{"why":"no n"},7,{"n":1},{"n":1}]"#, candidates: three)
        == [LAAdvice.Suggestion(file: "a.ckpt", weight: 0.8, why: "")])
  }

  @Test func weightsComeBackWithinTheRange() {
    let read = LAAdvice.parse(#"[{"n":1,"weight":99},{"n":2,"weight":-9},{"n":3,"weight":"x"}]"#, candidates: three)
    #expect(read?.map(\.weight) == [4, -4, 1])
  }

  @Test func atMostThreeAreKept() {
    let many = (1...8).map { LAAdvice.Candidate(lora: lora("L\($0)"), notes: "") }
    let answer = "[" + (1...7).map { #"{"n":\#($0)}"# }.joined(separator: ",") + "]"
    #expect(LAAdvice.parse(answer, candidates: many)?.map(\.file) == ["l1.ckpt", "l2.ckpt", "l3.ckpt"])
  }

  @Test func noListIsNotAnEmptyList() {
    #expect(LAAdvice.parse("[]", candidates: three) == [])
    #expect(LAAdvice.parse("Nessuno: []", candidates: three) == [])
    #expect(LAAdvice.parse("non so", candidates: three) == nil)
    #expect(LAAdvice.parse(#"{"n":1}"#, candidates: three) == nil)
    #expect(LAAdvice.parse("", candidates: three) == nil)
  }

  @Test func theContributionCarriesFileWeightAndTrigger() throws {
    let body = LAAdvice.contribution(lora("A", trigger: "aa", weight: 0.8))
    let sent = try #require((body["loras"] as? [[String: Any]])?.first)
    #expect(sent["file"] as? String == "a.ckpt" && sent["weight"] as? Double == 0.8 && sent["trigger"] as? String == "aa")
    #expect(sent.count == 3 && body.count == 1)
    #expect(((LAAdvice.contribution(lora("A"), weight: 0.5)["loras"] as? [[String: Any]])?.first?["weight"] as? Double) == 0.5)
    #expect(((LAAdvice.contribution(lora("A"), weight: 9)["loras"] as? [[String: Any]])?.first?["weight"] as? Double) == 4)
  }

  @Test func replacingAsksTheAppToTakeTheOthersOff() {
    #expect(LAAdvice.contribution(lora("A"), replacing: true)["replaceLoRAs"] as? Bool == true)
    #expect(LAAdvice.contribution(lora("A"))["replaceLoRAs"] == nil)
  }

  // MARK: The master prompt

  private func tempPrompts() -> DTHubPromptFolder {
    DTHubPromptFolder(folder: FileManager.default.temporaryDirectory.appendingPathComponent("la-prompt-\(UUID().uuidString)", isDirectory: true))
  }

  @Test func theBuiltInCopyIsTheFileOfTheData() throws {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Data/master-prompt.md")
    #expect(try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .newlines) == EmbeddedData.masterPrompt.trimmingCharacters(in: .newlines))
  }

  @Test func atMostThreeAndTheLanguageAreFilledIn() {
    #expect(LAAdvice.most == 3)
    let text = LAAdvice.system(italian: false, folder: tempPrompts())
    #expect(text.contains("at most 3 LoRAs") && text.contains("in English") && !text.contains("{max}") && !text.contains("{language}"))
  }

  @Test func installWritesTheMasterPromptAndCustom() {
    let folder = tempPrompts()
    folder.install([LAPrompts.masterPath: EmbeddedData.masterPrompt])
    #expect(FileManager.default.fileExists(atPath: folder.folder.appendingPathComponent("master-prompt.md").path))
    var isFolder: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: folder.folder.appendingPathComponent("custom").path, isDirectory: &isFolder) && isFolder.boolValue)
  }

  @Test func theUsersCustomFileIsAddedOrReplaces() throws {
    let folder = tempPrompts()
    folder.install([LAPrompts.masterPath: EmbeddedData.masterPrompt])
    let custom = folder.folder.appendingPathComponent("custom/master-prompt.md")
    try "Prefer LoRAs for skin.".write(to: custom, atomically: true, encoding: .utf8)
    let added = LAPrompts.system(italian: true, in: folder)
    #expect(added.contains("Pick at most 3") && added.hasSuffix("Prefer LoRAs for skin.") && added.contains(DTHubPromptFolder.priorityLine))
    try "---\nmode: replace\n---\nOnly {max} in {language}.".write(to: custom, atomically: true, encoding: .utf8)
    #expect(LAPrompts.system(italian: true, in: folder) == "Only 3 in italiano.")
  }

  @Test func aMasterPromptFileOfTheUserIsUsedWhenNotOlder() throws {
    let folder = tempPrompts()
    try FileManager.default.createDirectory(at: folder.folder, withIntermediateDirectories: true)
    try "---\nversion: 9\n---\nMy own, {max}.".write(to: folder.folder.appendingPathComponent("master-prompt.md"), atomically: true, encoding: .utf8)
    #expect(LAPrompts.system(italian: false, in: folder) == "My own, 3.")
    try "---\nversion: 0\n---\nOld".write(to: folder.folder.appendingPathComponent("master-prompt.md"), atomically: true, encoding: .utf8)
    #expect(LAPrompts.system(italian: false, in: folder).contains("Pick at most 3") && !LAPrompts.problems(in: folder).isEmpty)
  }
}
