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

  @Test func theSavedPresetKeepsPromptAndOriginButNoSize() {
    let file = tempFile()
    let store = PresetStore(fileURL: file)
    store.save(Preset(name: "P", prompt: "a cat", parameters: GenerationParameters(width: 512, height: 1536), origin: "com.x"))
    let again = PresetStore(fileURL: file).preset(named: "p")
    #expect(again?.prompt == "a cat" && again?.origin == "com.x")
    #expect(again?.parameters.width == GenerationParameters.default.width)
    #expect(again?.parameters.height == GenerationParameters.default.height)
  }

  @Test func aFileSavedBeforeHasNoPromptAndNoOrigin() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"[{"name":"old","model":"m.ckpt","negativePrompt":"blur","parameters":{"steps":9,"width":512}}]"#.utf8).write(to: file)
    let old = try #require(PresetStore(fileURL: file).preset(named: "old"))
    #expect(old.prompt.isEmpty && old.origin == nil && old.parameters.steps == 9)
  }
}

@MainActor
struct PresetReviewTests {
  func tempFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("PresetReviewTests-\(UUID())", isDirectory: true).appendingPathComponent("presets.json")
  }

  @Test func savingOverAPluginsPresetWithoutAnOriginKeepsItsOrigin() {
    let store = PresetStore(fileURL: tempFile())
    store.add(fromPlugin: [Preset(name: "Match", parameters: GenerationParameters(steps: 4), origin: "com.x")])
    // What the Save sheet does: a new Preset with the same name and no origin.
    store.save(Preset(name: "match", parameters: GenerationParameters(steps: 9)))
    #expect(store.preset(named: "Match")?.origin == "com.x" && store.preset(named: "Match")?.parameters.steps == 9)
    // A user's own preset stays the user's.
    store.save(Preset(name: "Mine"))
    store.save(Preset(name: "Mine", parameters: GenerationParameters(steps: 3)))
    #expect(store.preset(named: "Mine")?.origin == nil)
  }

  @Test func anUnreadablePresetFileIsKeptAsideNotOverwrittenByThePluginsPresets() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("this is {not json".utf8).write(to: file)
    let store = PresetStore(fileURL: file)
    #expect(store.presets.isEmpty)
    store.add(fromPlugin: [Preset(name: "One", origin: "com.x")])
    let aside = file.deletingLastPathComponent().appendingPathComponent("presets.unreadable.json")
    #expect(try String(contentsOf: aside, encoding: .utf8) == "this is {not json")
    #expect(PresetStore(fileURL: file).presets.map(\.name) == ["One"])
  }

  @Test func aReadableFileIsNotMovedAside() throws {
    let file = tempFile()
    PresetStore(fileURL: file).save(Preset(name: "A"))
    _ = PresetStore(fileURL: file)
    #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().appendingPathComponent("presets.unreadable.json").path))
  }
}
