import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct PresetPromptTests {
  let catalog = ModelCatalog(models: [], loras: [], fileCount: 0)

  func tempFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("PresetPromptTests-\(UUID())", isDirectory: true).appendingPathComponent("presets.json")
  }

  @Test func theTabsPromptStaysWhenThePresetHasNone() {
    let tab = GenerationFields(prompt: "my prompt", negativePrompt: "my negative")
    let without = PresetLoad.of(Preset(name: "a"), current: tab, catalog: catalog)
    #expect(without.prompt == "my prompt" && without.negativePrompt == "my negative")
    let with = PresetLoad.of(Preset(name: "b", prompt: "preset prompt"), current: tab, catalog: catalog)
    #expect(with.prompt == "preset prompt")
  }

  @Test func theCanvasSizeOfTheTabStaysWhateverThePresetSays() {
    var tab = GenerationFields()
    tab.parameters.width = 768
    tab.parameters.height = 1280
    let preset = Preset(name: "wide", parameters: GenerationParameters(width: 2048, height: 512, steps: 6))
    let load = PresetLoad.of(preset, current: tab, catalog: catalog)
    #expect(load.parameters.width == 768 && load.parameters.height == 1280)
    #expect(load.parameters.steps == 6)
  }

  @Test func aPresetWithoutTheTiledDiffusionBringsABigCanvasBackWithinTheLimit() {
    var tab = GenerationFields()
    tab.parameters.advanced.tiledDiffusion = true
    tab.parameters.width = 4096
    tab.parameters.height = 2048
    let load = PresetLoad.of(Preset(name: "plain"), current: tab, catalog: catalog)
    #expect(load.parameters.width == 2048 && load.parameters.height == 1024)
    var tiled = Preset(name: "tiled")
    tiled.parameters.advanced.tiledDiffusion = true
    #expect(PresetLoad.of(tiled, current: tab, catalog: catalog).parameters.width == 4096)
  }

  @Test func aSavedPresetKeepsItsPromptAndAFileWithoutOneHasNone() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PresetPromptTests-\(UUID())", isDirectory: true)
    let store = PresetStore(folder: folder)
    try store.save(Preset(name: "P", prompt: "a cat"))
    try Data(#"{"model":"m.ckpt","negativePrompt":"blur","parameters":{"steps":9,"width":512}}"#.utf8)
      .write(to: folder.appendingPathComponent("Old.json"))
    #expect(store.preset(named: "p")?.prompt == "a cat")
    let old = try #require(store.preset(named: "old"))
    #expect(old.prompt.isEmpty && old.parameters.steps == 9 && old.name == "Old")
  }
}
