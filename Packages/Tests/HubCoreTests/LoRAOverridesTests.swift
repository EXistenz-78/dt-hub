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
    #expect(overrides.entries[fox.file]?.weight == 2.5)
    overrides.setWeight(-9, for: fox)
    #expect(overrides.entries[fox.file]?.weight == -1.5)
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
}
