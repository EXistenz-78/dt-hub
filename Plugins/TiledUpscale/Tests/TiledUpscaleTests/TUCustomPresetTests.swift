import Foundation
import Testing

@testable import TiledUpscale

/// The `TUP…` presets of DT Hub the user picks from the menu, for a model the plug-in has no preset of its own for.
@MainActor
struct TUCustomPresetTests {
  private func presets(_ files: [String: String]) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tupc-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    for (name, json) in files { try json.write(to: url.appendingPathComponent("\(name).json"), atomically: true, encoding: .utf8) }
    return url
  }

  private let withLoRA = #"{"prompt":"enhance","parameters":{"steps":6,"guidanceScale":1.5,"sampler":3,"shift":2,"resolutionDependentShift":true,"loras":[{"file":"mine.ckpt","weight":0.8}]}}"#
  private let noLoRA = #"{"prompt":"","parameters":{"steps":4,"loras":[]}}"#

  private func state(folder: URL, family: String? = "krea_2") -> TUState {
    let s = TUState(store: TUStore(folder: nil), italian: false)
    s.family = family
    s.presetFolder = folder
    s.tempFolder = TestImages.temporaryFolder().path
    s.refreshPresets()
    return s
  }

  @Test func theMenuListsOnlyThePresetsThatStartWithTUP() throws {
    let folder = try presets(["TUP · Krea", "TUP my model", "PAN · 360 ERP", "Flux3 upscale", "tup lowercase"].reduce(into: [:]) { $0[$1] = noLoRA })
    #expect(TUPresetFile.names(in: folder) == ["TUP · Krea", "TUP my model"])
    #expect(TUPresetFile.names(in: nil).isEmpty)
  }

  @Test func theFileGivesThePresetItsValues() throws {
    let file = try #require(TUPresetFile.read(named: "TUP a", in: try presets(["TUP a": withLoRA])))
    let preset = TUPreset(name: "TUP a", file: file)
    #expect(preset.steps == 6 && preset.guidanceScale == 1.5 && preset.sampler == 3 && preset.shift == 2)
    #expect(preset.loraFile == "mine.ckpt" && preset.defaultLoRAWeight == 0.8 && preset.resolutionDependentShift)
    #expect(preset.fixedPrompt == "enhance" && preset.strength == 1)
  }

  @Test func aPresetWithoutLoRAHasNoneInThePasses() throws {
    let file = try #require(TUPresetFile.read(named: "TUP b", in: try presets(["TUP b": noLoRA])))
    let preset = TUPreset(name: "TUP b", file: file)
    #expect(preset.loraFile.isEmpty && preset.fixedPrompt == nil)
    #expect(preset.passLoras(weight: 1, file: file).isEmpty && preset.loras(weight: 1).isEmpty)
  }

  @Test func aModelWithoutAPresetOfItsOwnWorksOnceAPresetIsPicked() throws {
    let s = state(folder: try presets(["TUP my model": withLoRA]))
    s.setImage(TestImages.solid(512, 512, (1, 2, 3)), name: "a")
    #expect(s.automaticPreset == nil && !s.canPrepare)
    #expect(s.automaticPresetLabel == TUState.text(.presetNoneForModel, italian: false))
    s.presetName = "TUP my model"
    #expect(s.canPrepare && s.preset?.name == "TUP my model")
    #expect(s.loraWeight == 0.8, "the LoRA strength starts at the preset's own")
  }

  @Test func theChosenPresetBeatsTheAutomaticOneAndAMissingFileFallsBack() throws {
    let folder = try presets(["TUP my model": withLoRA])
    let s = state(folder: folder, family: "flux2_9b")
    #expect(s.preset?.name == TUPresetTable.fluxKlein9BName)
    s.presetName = "TUP my model"
    #expect(s.preset?.name == "TUP my model")
    try FileManager.default.removeItem(at: folder.appendingPathComponent("TUP my model.json"))
    #expect(s.preset?.name == TUPresetTable.fluxKlein9BName, "the file is gone: the plug-in's own preset")
    #expect(s.presetMenuNames == ["TUP my model"], "a pick whose file is gone stays in the menu until another is chosen")
  }

  @Test func thePickIsKeptPerProjectAndChangingItUnpreparesTheJob() throws {
    let s = state(folder: try presets(["TUP my model": withLoRA]))
    let one = TestImages.temporaryFolder().appendingPathComponent("one")
    let two = TestImages.temporaryFolder().appendingPathComponent("two")
    s.switchProject(folder: one)
    s.presetName = "TUP my model"
    s.switchProject(folder: two)
    #expect(s.presetName == nil)
    s.switchProject(folder: one)
    #expect(s.presetName == "TUP my model")
    #expect(s.currentChoice.presetName == "TUP my model")
  }
}
