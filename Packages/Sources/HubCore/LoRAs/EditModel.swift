import HubKit

/// Whether the current model counts as an Edit model: the model itself is one (its specification says so), or one of
/// the selected LoRAs is of category `edit` in the catalog. A LoRA the catalog does not know does not count.
public enum EditModel {
  public static func isEdit(model: CatalogModel?, loras: [LoRASelection], catalog: ModelCatalog) -> Bool {
    if model?.capabilities.isEditModel == true { return true }
    let editFiles = Set(catalog.loras.filter { $0.category == "edit" }.map(\.file))
    return loras.contains { editFiles.contains($0.file) }
  }
}
