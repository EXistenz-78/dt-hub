import Foundation
import Testing

@testable import TiledUpscale

struct TUPresetFileTests {
  private func folder(with json: String?, named name: String = "TUP · FLUX.3 klein") throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tupf-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    if let json { try json.write(to: url.appendingPathComponent("\(name).json"), atomically: true, encoding: .utf8) }
    return url
  }

  private let saved = """
    {"model":"","prompt":"my own prompt","parameters":{"steps":8,"loras":[{"file":"mine_lora_f16.ckpt","weight":0.7,"mode":0}]}}
    """

  @Test func readsThePromptAndTheFirstLoRAOfTheFile() throws {
    let file = try #require(TUPresetFile.read(named: "TUP · FLUX.3 klein", in: try folder(with: saved)))
    #expect(file.prompt == "my own prompt")
    #expect(file.loraFile == "mine_lora_f16.ckpt")
  }

  @Test func noFileOrNoFolderIsNil() throws {
    #expect(TUPresetFile.read(named: "TUP · FLUX.3 klein", in: try folder(with: nil)) == nil)
    #expect(TUPresetFile.read(named: "TUP · FLUX.3 klein", in: nil) == nil)
    #expect(TUPresetFile.read(named: "TUP · FLUX.3 klein", in: try folder(with: "not json")) == nil)
  }

  @Test func aPassSendsNoFieldsWhenThereAreNoInstructions() throws {
    let preset = try #require(TUPresetTable.preset(forFamily: "flux3_5b"))
    #expect(preset.passFields(extra: "  ", file: nil).isEmpty, "the preset the user saved decides steps, shift and prompt")
  }

  @Test func theInstructionsAreAddedToThePromptOfTheFileOrOfTheTable() throws {
    let preset = try #require(TUPresetTable.preset(forFamily: "flux3_5b"))
    let file = TUPresetFile(prompt: "my own prompt", loraFile: nil)
    #expect(preset.passFields(extra: "keep the sky", file: file)["prompt"] as? String == "my own prompt keep the sky")
    #expect(preset.passFields(extra: "keep the sky", file: nil)["prompt"] as? String == "\(TUPresetTable.flux3Prompt) keep the sky")
  }

  @Test func theLoRAFileComesFromThePresetAndTheWeightFromThePlugin() throws {
    let preset = try #require(TUPresetTable.preset(forFamily: "flux3_5b"))
    let mine = preset.passLoras(weight: 0.4, file: TUPresetFile(prompt: nil, loraFile: "mine_lora_f16.ckpt"))
    #expect(mine.count == 1 && mine[0]["file"] as? String == "mine_lora_f16.ckpt" && mine[0]["weight"] as? Double == 0.4)
    let table = preset.passLoras(weight: 2, file: nil)
    #expect(table[0]["file"] as? String == TUPresetTable.flux3LoRA && table[0]["weight"] as? Double == 2)
  }

  @Test func theRegisteredPresetHasTheFixedPromptNeverTheInstructions() throws {
    let preset = try #require(TUPresetTable.preset(forFamily: "flux3_5b"))
    #expect(preset.fields(prompt: preset.prompt(trigger: ""))["prompt"] as? String == TUPresetTable.flux3Prompt)
  }
}
