import Foundation
import HubKit
import Testing

@testable import HubCore

/// Whether a model counts as an Edit model: the model itself, or one of the selected LoRAs of category `edit`.
struct EditModelTests {
  private let editModel = CatalogModel(
    file: "kontext.ckpt", name: "Kontext", family: "flux1",
    capabilities: ModelCapabilities(
      guidanceEmbed: true, teaCache: false, clipL: true, openClipG: false, t5: true, optionalT5: false,
      clipSkip: false, nativeSize: nil, modifier: "kontext"))
  private let plainModel = CatalogModel(file: "flux.ckpt", name: "Flux", family: "flux2_9b")
  private let editLoRA = CatalogLoRA(file: "edit.ckpt", name: "Edit", family: nil, category: "edit")
  private let styleLoRA = CatalogLoRA(file: "style.ckpt", name: "Style", family: nil, category: "style")

  private var catalog: ModelCatalog {
    ModelCatalog(models: [editModel, plainModel], loras: [editLoRA, styleLoRA], fileCount: 4)
  }

  @Test func anEditModelIsEdit() {
    #expect(EditModel.isEdit(model: editModel, loras: [], catalog: catalog))
  }

  @Test func aNonEditModelWithAnEditLoRAIsEdit() {
    let loras = [LoRASelection(file: "edit.ckpt")]
    #expect(EditModel.isEdit(model: plainModel, loras: loras, catalog: catalog))
  }

  @Test func aNonEditModelWithOtherLoRAsIsNot() {
    let loras = [LoRASelection(file: "style.ckpt")]
    #expect(!EditModel.isEdit(model: plainModel, loras: loras, catalog: catalog))
  }

  @Test func noModelAndNoLoRAsIsNot() {
    #expect(!EditModel.isEdit(model: nil, loras: [], catalog: catalog))
  }

  @Test func noModelButAnEditLoRAIsEdit() {
    let loras = [LoRASelection(file: "edit.ckpt")]
    #expect(EditModel.isEdit(model: nil, loras: loras, catalog: catalog))
  }

  @Test func aLoRAUnknownToTheCatalogDoesNotCount() {
    let loras = [LoRASelection(file: "unknown_edit.ckpt")]
    #expect(!EditModel.isEdit(model: plainModel, loras: loras, catalog: catalog))
  }

  @Test func anEmptyCatalogDoesNotCount() {
    let empty = ModelCatalog(models: [], loras: [], fileCount: 0)
    let loras = [LoRASelection(file: "edit.ckpt")]
    #expect(!EditModel.isEdit(model: plainModel, loras: loras, catalog: empty))
  }

  @Test func anEditLoRAOfAnotherFamilyDoesNotCount() {
    let other = CatalogLoRA(file: "qwen_edit.ckpt", name: "QE", family: "qwen_image", category: "edit")
    let cat = ModelCatalog(models: [plainModel], loras: [other], fileCount: 2)
    let loras = [LoRASelection(file: "qwen_edit.ckpt")]
    #expect(!EditModel.isEdit(model: plainModel, loras: loras, catalog: cat))
  }

  @Test func anEditLoRAOfTheModelsOwnFamilyCounts() {
    let own = CatalogLoRA(file: "own_edit.ckpt", name: "OE", family: "flux2_9b", category: "edit")
    let cat = ModelCatalog(models: [plainModel], loras: [own], fileCount: 2)
    let loras = [LoRASelection(file: "own_edit.ckpt")]
    #expect(EditModel.isEdit(model: plainModel, loras: loras, catalog: cat))
  }

  @Test func withNoModelAnEditLoRAOfAnyFamilyCounts() {
    let other = CatalogLoRA(file: "qwen_edit.ckpt", name: "QE", family: "qwen_image", category: "edit")
    let cat = ModelCatalog(models: [], loras: [other], fileCount: 1)
    #expect(EditModel.isEdit(model: nil, loras: [LoRASelection(file: "qwen_edit.ckpt")], catalog: cat))
  }
}
