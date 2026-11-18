import HubKit
import Testing

@testable import HubCore

struct JobComposerEditLoRATests {
  let krea = CatalogModel(file: "krea_2.ckpt", name: "Krea 2", family: "krea_2")
  let edit = CatalogLoRA(file: "edit_lora_f16.ckpt", name: "Edit", family: "krea_2", category: "edit")
  let style = CatalogLoRA(file: "style_lora_f16.ckpt", name: "Style", family: "krea_2", category: "style")

  func editFiles(selecting files: [String]) -> [[String]?] {
    var parameters = GenerationParameters()
    parameters.loras = files.map { LoRASelection(file: $0) }
    let catalog = ModelCatalog(models: [krea], loras: [edit, style], fileCount: 3)
    return JobComposer.batches(
      prompt: "p", negativePrompt: "", model: krea.file, family: krea.family, parameters: parameters, catalog: catalog
    ) { 1 }.map(\.editLoRAFiles)
  }

  @Test func theJobNamesTheEditLoRAsItSends() {
    let sent = editFiles(selecting: ["edit_lora_f16.ckpt", "style_lora_f16.ckpt"])
    #expect(!sent.isEmpty && sent.allSatisfy { $0 == ["edit_lora_f16.ckpt"] })
  }

  @Test func withoutAnEditLoRAThereIsNothingToName() {
    #expect(editFiles(selecting: ["style_lora_f16.ckpt"]).allSatisfy { $0 == nil })
  }
}
