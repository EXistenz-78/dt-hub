import DTHubPluginKit
import Foundation
import Testing

@testable import CharacterSheet

@Suite("CSBrief")
struct CSBriefTests {
  @Test func peDetectionReadsTheModelName() {
    #expect(CSBrief.isPEI2I("Qwen-Image-2.1-PE-I2I-MLX-4bit"))
    #expect(CSBrief.isPEI2I("qwen3.5_9b_qwen_image_2.1_pe_i2i"))
    #expect(!CSBrief.isPEI2I("Qwen-Image-2.1-PE-T2I-MLX-4bit"))
    #expect(!CSBrief.isPEI2I("Qwen3-VL-8B-Instruct-4bit"))
    #expect(!CSBrief.isPEI2I(""))
  }

  @Test func genericRequest() {
    let request = CSBrief.generic(
      model: "Qwen3-VL-8B-Instruct-4bit", image: "/t/ref.png", name: "Ayaka", master: "MASTER")
    #expect(request.model == "Qwen3-VL-8B-Instruct-4bit")
    #expect(request.system == "MASTER")
    #expect(request.prompt == "Entity name: Ayaka")
    #expect(request.images == ["/t/ref.png"])
    #expect(
      request.options
        == DTHubLLMOptions(temperature: 0.9, topP: 0.95, topK: 20, maxTokens: 16384, thinking: true, timeout: 900))
  }

  @Test func genericRequestWithAnEmptyNameUsesCHARACTER() {
    let request = CSBrief.generic(model: "m", image: "/t/ref.png", name: "  ", master: "MASTER")
    #expect(request.prompt == "Entity name: CHARACTER")
  }

  @Test func peRequest() {
    let request = CSBrief.peI2I(
      model: "Qwen-Image-2.1-PE-I2I-MLX-4bit", image: "/t/ref.png", name: "Ayaka", master: "MASTER",
      peSystem: "PE SYSTEM")
    #expect(request.model == "Qwen-Image-2.1-PE-I2I-MLX-4bit")
    #expect(request.system == "PE SYSTEM")
    #expect(request.prompt == "MASTER\n\nEntity name: Ayaka")
    #expect(request.images == ["/t/ref.png"])
    #expect(
      request.options
        == DTHubLLMOptions(
          temperature: 1.0, topP: 0.95, topK: 20, presencePenalty: 0, maxTokens: 24000, thinking: true, timeout: 1800))
  }

  @Test func peSystemTakesTheFirstNonEmptyFile() {
    let folder = URL(fileURLWithPath: "/models/pe")
    let files = [
      "/models/pe/system_prompt.txt": "  \n",
      "/models/pe/system_prompt_i2i.txt": "Text\n",
    ]
    #expect(CSBrief.peSystem(inFolder: folder, read: { files[$0.path] }) == "Text")
  }

  @Test func peSystemWithNoUsableFileIsNil() {
    let folder = URL(fileURLWithPath: "/models/pe")
    let blank = ["/models/pe/system_prompt.txt": " ", "/models/pe/system_prompt_i2i.txt": "\n\n"]
    #expect(CSBrief.peSystem(inFolder: folder, read: { blank[$0.path] }) == nil)
    #expect(CSBrief.peSystem(inFolder: folder, read: { _ in nil }) == nil)
  }
}
