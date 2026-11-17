import Foundation
import HubKit
import Testing

@testable import HubCore

/// The user's own trigger words and weights for the LoRAs of the server (`loras.json`).
struct LoRAOverridesTests {
  let fox = CatalogLoRA(file: "fox_lora_f16.ckpt", name: "Fox", family: "flux2_9b", trigger: "foxstyle", defaultWeight: 0.7)
  let bare = CatalogLoRA(file: "bare_lora_f16.ckpt", name: "Bare", family: nil)

  private func catalog(_ loras: [CatalogLoRA]) -> ModelCatalog {
    ModelCatalog(
      models: [CatalogModel(file: "a.ckpt", name: "A", family: "flux2_9b")], loras: loras, fileCount: 3,
      upscalers: ["up.ckpt"], faceRestorers: ["face.ckpt"])
  }

  @Test func theServersTriggerIsInheritedUntilTheUserChangesIt() {
    var overrides = LoRAOverrides()
    #expect(overrides.apply(to: catalog([fox])).loras.first?.trigger == "foxstyle")
    overrides.setTrigger("my fox", for: fox)
    #expect(overrides.apply(to: catalog([fox])).loras.first?.trigger == "my fox")
  }

  @Test func anEmptiedTriggerMeansNoTriggerEvenIfTheServerHasOne() {
    var overrides = LoRAOverrides()
    overrides.setTrigger("", for: fox)
    #expect(overrides.apply(to: catalog([fox])).loras.first?.trigger == "")
    #expect(overrides.entries[fox.file]?.trigger == "")
  }

  @Test func aServerWithoutATriggerMeansNoTrigger() {
    #expect(LoRAOverrides().apply(to: catalog([bare])).loras.first?.trigger == "")
  }

  @Test func typingTheServersOwnWordGoesBackToInheriting() {
    var overrides = LoRAOverrides()
    overrides.setTrigger("other", for: fox)
    overrides.setTrigger("  foxstyle ", for: fox)
    #expect(overrides.entries[fox.file] == nil)
    #expect(!overrides.isChanged(fox))
  }

  @Test func theTriggerIsTrimmed() {
    var overrides = LoRAOverrides()
    overrides.setTrigger("  my fox \n", for: fox)
    #expect(overrides.entries[fox.file]?.trigger == "my fox")
  }

  @Test func theWeightIsOneForEveryoneWhateverTheServerSays() {
    #expect(LoRAOverrides().apply(to: catalog([fox, bare])).loras.map(\.defaultWeight) == [1, 1])
  }

  @Test func theUsersWeightWins() {
    var overrides = LoRAOverrides()
    overrides.setWeight(0.35, for: fox)
    #expect(overrides.apply(to: catalog([fox, bare])).loras.map(\.defaultWeight) == [0.35, 1])
  }

  @Test func theWeightStaysInsideTheRange() {
    var overrides = LoRAOverrides()
    overrides.setWeight(9, for: fox)
    #expect(overrides.entries[fox.file]?.weight == 4)
    overrides.setWeight(-9, for: fox)
    #expect(overrides.entries[fox.file]?.weight == -4)
  }

  @Test func aWeightOfOneOrNoneIsNoOverride() {
    var overrides = LoRAOverrides()
    overrides.setWeight(0.5, for: fox)
    overrides.setWeight(1, for: fox)
    #expect(overrides.entries[fox.file] == nil)
    overrides.setWeight(0.5, for: fox)
    overrides.setWeight(nil, for: fox)
    #expect(overrides.entries[fox.file] == nil)
  }

  @Test func resettingBringsBackTheServersValues() {
    var overrides = LoRAOverrides()
    overrides.setTrigger("mine", for: fox)
    overrides.setWeight(0.4, for: fox)
    #expect(overrides.isChanged(fox))
    overrides.reset(fox)
    #expect(!overrides.isChanged(fox))
    let merged = overrides.apply(to: catalog([fox])).loras.first
    #expect(merged?.trigger == "foxstyle" && merged?.defaultWeight == 1)
  }

  @Test func onlyTheTriggerCanBeChangedOrOnlyTheWeight() {
    var overrides = LoRAOverrides()
    overrides.setWeight(0.4, for: fox)
    #expect(overrides.entries[fox.file]?.trigger == nil)
    #expect(overrides.apply(to: catalog([fox])).loras.first?.trigger == "foxstyle")
    overrides.setTrigger("mine", for: fox)
    overrides.setWeight(1, for: fox)
    #expect(overrides.entries[fox.file]?.weight == nil && overrides.entries[fox.file]?.trigger == "mine")
  }

  @Test func theRestOfTheCatalogIsUntouched() {
    var overrides = LoRAOverrides()
    overrides.setTrigger("mine", for: fox)
    let original = catalog([fox, bare])
    let merged = overrides.apply(to: original)
    #expect(merged.models == original.models)
    #expect(merged.fileCount == original.fileCount)
    #expect(merged.upscalers == original.upscalers && merged.faceRestorers == original.faceRestorers)
    #expect(merged.loras.map(\.file) == original.loras.map(\.file))
    #expect(merged.loras.map(\.name) == ["Fox", "Bare"] && merged.loras.map(\.family) == ["flux2_9b", nil])
  }

  @Test func entriesOfLoRAsThatLeftTheServerAreKeptAndIgnored() {
    var overrides = LoRAOverrides()
    overrides.setTrigger("mine", for: fox)
    let merged = overrides.apply(to: catalog([bare]))
    #expect(merged.loras.map(\.file) == [bare.file])
    #expect(overrides.entries[fox.file]?.trigger == "mine")
  }

  // MARK: Min / Base / Max

  @Test func theThreeWeightsReachTheCatalog() {
    var overrides = LoRAOverrides()
    overrides.setWeights(min: 0.4, base: 0.8, max: 1.2, for: fox)
    let lora = overrides.apply(to: catalog([fox])).loras[0]
    #expect(lora.minWeight == 0.4 && lora.defaultWeight == 0.8 && lora.maxWeight == 1.2)
    #expect(overrides.apply(to: catalog([bare])).loras[0].minWeight == nil)
  }

  @Test func theBaseStaysBetweenTheLimitsAndEverythingInTheRange() {
    var overrides = LoRAOverrides()
    overrides.setWeights(min: 0.5, base: 0.1, max: 0.9, for: fox)
    #expect(overrides.entries[fox.file]?.weight == 0.5)
    overrides.setWeights(min: 0.5, base: 3, max: 0.9, for: fox)
    #expect(overrides.entries[fox.file]?.weight == 0.9)
    overrides.setWeights(min: -9, base: nil, max: 9, for: fox)
    #expect(overrides.entries[fox.file]?.minWeight == -4 && overrides.entries[fox.file]?.maxWeight == 4)
    overrides.setWeights(min: 2, base: nil, max: 1, for: fox)
    #expect(overrides.entries[fox.file]?.minWeight == 1 && overrides.entries[fox.file]?.maxWeight == 1)
  }

  @Test func clearingAllThreeRemovesTheEntry() {
    var overrides = LoRAOverrides()
    overrides.setWeights(min: 0.4, base: 0.8, max: 1.2, for: fox)
    overrides.setWeights(min: nil, base: nil, max: nil, for: fox)
    #expect(overrides.entries[fox.file] == nil)
  }

  @Test func theTriggerSurvivesAChangeOfWeights() {
    var overrides = LoRAOverrides()
    overrides.setTrigger("mine", for: fox)
    overrides.setWeights(min: 0.4, base: nil, max: nil, for: fox)
    #expect(overrides.entries[fox.file]?.trigger == "mine")
  }

  @Test func withALimitTheBaseIsWrittenEvenWhenItIsTheDefault() {
    var overrides = LoRAOverrides()
    overrides.setWeights(min: 0.4, base: 1, max: 1.5, for: fox)
    #expect(overrides.entries[fox.file]?.weight == 1 && overrides.entries[fox.file]?.minWeight == 0.4 && overrides.entries[fox.file]?.maxWeight == 1.5)
    overrides.setWeights(min: nil, base: 1, max: nil, for: fox)
    #expect(overrides.entries[fox.file] == nil)
  }

  @Test func aSettingsUpdateSetsKeepsAndClearsEachField() {
    var overrides = LoRAOverrides()
    overrides.apply(
      LoRASettingsUpdate(trigger: .set("my fox"), category: .set("turbo"), steps: .set(4), guidance: .set(1.5), shift: .set(3)),
      for: fox)
    let entry = overrides.entries[fox.file]
    #expect(entry?.trigger == "my fox" && entry?.category == "turbo" && entry?.steps == 4)
    #expect(entry?.guidance == 1.5 && entry?.shift == 3)
    let before = overrides
    overrides.apply(LoRASettingsUpdate(), for: fox)
    #expect(overrides == before)
    overrides.apply(LoRASettingsUpdate(category: .clear), for: fox)
    #expect(overrides.entries[fox.file]?.category == nil && overrides.entries[fox.file]?.steps == 4)
    overrides.apply(LoRASettingsUpdate(trigger: .set("")), for: fox)
    #expect(overrides.entries[fox.file]?.trigger == "")
    overrides.apply(LoRASettingsUpdate(trigger: .clear), for: fox)
    #expect(overrides.entries[fox.file]?.trigger == nil)
    overrides.apply(LoRASettingsUpdate(steps: .clear, guidance: .clear, shift: .clear), for: fox)
    #expect(overrides.entries[fox.file] == nil)
  }

  @Test func anUnknownCategoryIsRefused() {
    var overrides = LoRAOverrides()
    overrides.apply(LoRASettingsUpdate(category: .set("style")), for: fox)
    overrides.apply(LoRASettingsUpdate(category: .set("banana")), for: fox)
    #expect(overrides.entries[fox.file]?.category == "style")
    #expect(LoRAOverrides.categories == ["character", "style", "slider", "edit", "turbo"])
  }

  @Test func numbersAreBroughtIntoRange() {
    var overrides = LoRAOverrides()
    overrides.apply(LoRASettingsUpdate(steps: .set(900), guidance: .set(-3), shift: .set(80)), for: fox)
    let entry = overrides.entries[fox.file]
    #expect(entry?.steps == 200 && entry?.guidance == 0 && entry?.shift == 50)
    overrides.apply(LoRASettingsUpdate(steps: .set(0), guidance: .set(.nan), shift: .set(.infinity)), for: fox)
    #expect(overrides.entries[fox.file]?.steps == 1)
    #expect(overrides.entries[fox.file]?.guidance == 0 && overrides.entries[fox.file]?.shift == 50)
  }

  @Test func theCatalogCarriesTheNewFields() {
    var overrides = LoRAOverrides()
    overrides.apply(
      LoRASettingsUpdate(category: .set("turbo"), steps: .set(4), guidance: .set(1.5), shift: .set(3)), for: fox)
    let lora = overrides.apply(to: catalog([fox, bare])).loras
    #expect(lora[0].category == "turbo" && lora[0].steps == 4 && lora[0].guidance == 1.5 && lora[0].shift == 3)
    #expect(lora[1].category == nil && lora[1].steps == nil && lora[1].guidance == nil && lora[1].shift == nil)
  }

  @Test func anEntryWithOnlyACategoryIsChanged() {
    var overrides = LoRAOverrides()
    overrides.apply(LoRASettingsUpdate(category: .set("slider")), for: fox)
    #expect(overrides.isChanged(fox))
    #expect(!LoRAOverride(category: "slider").isEmpty)
    #expect(LoRAOverride().isEmpty)
  }
}
