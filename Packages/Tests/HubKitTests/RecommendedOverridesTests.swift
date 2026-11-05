import Foundation
import Testing

@testable import HubKit

struct RecommendedOverridesTests {
  let base = RecommendedSettings(
    data: Data(
      """
      {"models":{"flux_2_klein_9b":{"steps":4,"guidanceScale":1,"sampler":16,"shift":3}},
       "families":{"v1":{"steps":16,"guidanceScale":5,"sampler":12}}}
      """.utf8))

  private func tab() -> GenerationParameters {
    var parameters = GenerationParameters()
    parameters.steps = 16
    parameters.guidanceScale = 4
    parameters.sampler = .uniPC
    parameters.shift = 3
    parameters.resolutionDependentShift = false
    parameters.loras = [
      LoRASelection(file: "a_lora_f16.ckpt", weight: 0.8, mode: .base, trigger: "pan360"),
      LoRASelection(file: "b_lora_f16.ckpt", weight: 1.2),
    ]
    return parameters
  }

  @Test func savingCapturesTheSamplingValuesAndTheLoRAs() {
    let values = RecommendedValues(capturing: tab())
    #expect(values.steps == 16 && values.guidanceScale == 4 && values.sampler == .uniPC)
    #expect(values.shift == 3 && values.resolutionDependentShift == false)
    #expect(values.loras == tab().loras)
  }

  @Test func theOverrideWinsOverTheBaseAndTheFamilyStaysAsItWas() {
    let saved = RecommendedSettings().setting(RecommendedValues(capturing: tab()), forFile: "flux_2_klein_9b_q6p.ckpt")
    let layered = base.overriding(with: saved)
    #expect(layered.values(forFile: "flux_2_klein_9b_f16.ckpt", family: nil)?.steps == 16)
    #expect(layered.values(forFile: "juggernaut_q6p.ckpt", family: "v1")?.steps == 16)
    #expect(layered.values(forFile: "juggernaut_q6p.ckpt", family: "v1")?.loras == nil)
    // Layering is also done after the online list is merged: the override still wins.
    let live = RecommendedSettings(
      models: ["flux_2_klein_9b": RecommendedValues(steps: 99, guidanceScale: 9, sampler: .dpmpp2mKarras)])
    #expect(base.merging(live).overriding(with: saved).values(forFile: "flux_2_klein_9b.ckpt", family: nil)?.steps == 16)
  }

  @Test func removingTheEntryGivesBackWhatTheBaseSays() {
    let saved = RecommendedSettings().setting(RecommendedValues(capturing: tab()), forFile: "flux_2_klein_9b_q6p.ckpt")
    #expect(saved.hasModel(forFile: "flux_2_klein_9b_f16.ckpt"))
    let removed = saved.removingModel(forFile: "flux_2_klein_9b_f16.ckpt")
    #expect(!removed.hasModel(forFile: "flux_2_klein_9b_f16.ckpt"))
    #expect(base.overriding(with: removed).values(forFile: "flux_2_klein_9b.ckpt", family: nil)?.steps == 4)
  }

  @Test func theFileRoundTripsWithItsLoRAsAndLeavesOutDamagedOnes() throws {
    let saved = RecommendedSettings().setting(RecommendedValues(capturing: tab()), forFile: "flux_2_klein_9b_q6p.ckpt")
    let again = RecommendedSettings(data: saved.encoded())
    #expect(again == saved)
    #expect(again.values(forFile: "flux_2_klein_9b.ckpt", family: nil)?.loras?.first?.trigger == "pan360")
    let damaged = RecommendedSettings(
      data: Data(
        """
        {"models":{"m":{"steps":4,"guidanceScale":1,"sampler":16,"loras":[{"file":"ok.ckpt","weight":0.5},{"weight":1},7]},
                   "n":{"steps":4,"guidanceScale":1,"sampler":16,"loras":[]}}}
        """.utf8))
    #expect(damaged.values(forFile: "m.ckpt", family: nil)?.loras == [LoRASelection(file: "ok.ckpt", weight: 0.5)])
    // An empty list is kept: it means "no LoRAs", not "leave them".
    #expect(damaged.values(forFile: "n.ckpt", family: nil)?.loras == [])
  }

  @Test func theStoreKeepsTheFileAndTreatsAMissingOrBrokenOneAsEmpty() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("overrides-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = RecommendedOverridesStore(fileURL: folder.appendingPathComponent("recommended-overrides.json"))
    #expect(store.load() == .empty)
    let saved = RecommendedSettings().setting(RecommendedValues(capturing: tab()), forFile: "x_f16.ckpt")
    store.save(saved)
    #expect(store.load() == saved)
    try Data("garbage".utf8).write(to: store.fileURL)
    #expect(store.load() == .empty)
  }

  @Test func applyingValuesWithLoRAsReplacesTheListAndDropsTheMissingOnes() {
    let values = RecommendedValues(capturing: tab())
    let result = GenerationParameters().applying(values, installedLoRAs: ["a_lora_f16.ckpt"])
    #expect(result.steps == 16 && result.sampler == .uniPC)
    #expect(result.loras.map(\.file) == ["a_lora_f16.ckpt"])
    #expect(result.loras.first?.trigger == "pan360")
    #expect(values.missingLoRAs(installed: ["a_lora_f16.ckpt"]) == ["b_lora_f16.ckpt"])
    // Nothing known about the server: nothing is filtered.
    #expect(GenerationParameters().applying(values, installedLoRAs: nil).loras.count == 2)
  }

  @Test func valuesWithoutALoRAListLeaveTheTabsLoRAs() {
    var current = GenerationParameters()
    current.loras = [LoRASelection(file: "keep.ckpt")]
    let result = current.applying(RecommendedValues(steps: 4, guidanceScale: 1, sampler: .uniPC), installedLoRAs: [])
    #expect(result.loras.map(\.file) == ["keep.ckpt"])
    // An explicit empty list clears them.
    let cleared = current.applying(
      RecommendedValues(steps: 4, guidanceScale: 1, sampler: .uniPC, loras: []), installedLoRAs: [])
    #expect(cleared.loras.isEmpty)
  }
}
