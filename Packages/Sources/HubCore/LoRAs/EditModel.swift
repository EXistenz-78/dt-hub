import HubKit

/// Whether the current model counts as an Edit model: the model itself is one (its specification says so), or one of
/// the selected LoRAs is of category `edit` in the catalog and is sent with the model's family (`LoRAStatus.usable`).
/// A LoRA the catalog does not know, or one made for another family (kept in the card, never sent), does not count.
/// With no model the family is unknown, as in the LoRA card: any LoRA the catalog knows counts.
public enum EditModel {
  public static func isEdit(model: CatalogModel?, loras: [LoRASelection], catalog: ModelCatalog) -> Bool {
    if model?.capabilities.isEditModel == true { return true }
    let editFiles = Set(catalog.loras.filter { $0.category == "edit" }.map(\.file))
    return loras.contains {
      editFiles.contains($0.file) && catalog.status(of: $0, family: model?.family) == .usable
    }
  }
}
