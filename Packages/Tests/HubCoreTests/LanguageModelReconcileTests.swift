import Foundation
import HubKit
import Testing

@testable import HubCore

struct LanguageModelReconcileTests {
  func model(_ name: String, vision: Bool = false) -> LanguageModelDescriptor {
    LanguageModelDescriptor(path: "/m/\(name)", name: name, sizeBytes: 1, supportsImages: vision)
  }
  func a(_ family: LanguageModelFamily, _ use: LanguageModelUse) -> LanguageModelAssignment {
    LanguageModelAssignment(family: family, use: use)
  }
  let allBoth = LanguageModelAssignment(family: .allOthers, use: .both)
  let noneBoth = LanguageModelAssignment(family: .none, use: .both)

  @Test func theModelChosenBefore0_1_4BecomesAllOthers() {
    let settings = LanguageModelSettings(selectedModel: "/m/vl")
    let r = LanguageModelAssignments.reconciled(settings, models: [model("txt"), model("vl", vision: true)])
    #expect(r == ["vl": allBoth, "txt": noneBoth])
  }

  @Test func aChosenModelThatIsGoneMigratesNothing() {
    let settings = LanguageModelSettings(selectedModel: "/m/gone")
    let r = LanguageModelAssignments.reconciled(settings, models: [model("txt"), model("vl")])
    #expect(r == ["vl": noneBoth, "txt": noneBoth])
  }

  @Test func aSingleModelNeedsNoSetup() {
    let r = LanguageModelAssignments.reconciled(LanguageModelSettings(), models: [model("only")])
    #expect(r == ["only": allBoth])
    let onNone = LanguageModelSettings(assignments: ["only": noneBoth])
    #expect(LanguageModelAssignments.reconciled(onNone, models: [model("only")]) == ["only": allBoth])
  }

  @Test func aFamilyAssignmentIsNeverTouched() {
    let mine = a(.family("qwen_image_2.1"), .enhance)
    let settings = LanguageModelSettings(assignments: ["only": mine])
    #expect(LanguageModelAssignments.reconciled(settings, models: [model("only")]) == ["only": mine])
  }

  @Test func aSingleModelDoesNotTakeAllOthersFromSomeoneAbsent() {
    let settings = LanguageModelSettings(assignments: ["gone": allBoth])
    let r = LanguageModelAssignments.reconciled(settings, models: [model("only")])
    #expect(r == ["gone": allBoth, "only": noneBoth])
  }

  @Test func theDownloadedModelTakesAllOthersWhenFree() {
    let name = "mlx-community/Qwen3-VL-8B-Instruct-4bit"
    let models = [model(name, vision: true), model("pe")]
    let settings = LanguageModelSettings(assignments: ["pe": a(.family("qwen_image_2.1"), .enhance)])
    let r = LanguageModelAssignments.reconciled(settings, models: models, downloaded: name)
    #expect(r[name] == allBoth)
    let taken = LanguageModelSettings(assignments: ["pe": allBoth])
    #expect(LanguageModelAssignments.reconciled(taken, models: models, downloaded: name)[name] == noneBoth)
  }

  @Test func newModelsStartOnNoneBothAndAbsentOnesAreKept() {
    let settings = LanguageModelSettings(assignments: ["vl": allBoth, "gone": a(.family("x"), .describe)])
    let r = LanguageModelAssignments.reconciled(settings, models: [model("vl"), model("new")])
    #expect(r == ["vl": allBoth, "new": noneBoth, "gone": a(.family("x"), .describe)])
  }
}

extension LanguageModelReconcileTests {
  @Test func aNewOldStyleChoiceTakesAllOthersFromTheCurrentHolder() {
    let settings = LanguageModelSettings(
      selectedModel: "/m/b", assignments: ["a": LanguageModelAssignment(family: .allOthers, use: .both)])
    let r = LanguageModelAssignments.reconciled(settings, models: [model("a"), model("b")])
    #expect(r["b"] == allBoth)
    #expect(r["a"] == noneBoth)
  }
}
