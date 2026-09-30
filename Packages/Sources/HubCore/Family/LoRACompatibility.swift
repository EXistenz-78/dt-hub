import HubKit

/// Whether a chosen LoRA is sent with the next RUN.
public enum LoRAStatus: Equatable, Sendable {
  case usable
  /// Made for another family (named): kept in the card, not sent.
  case otherFamily(String)
  /// The server does not list it (any more): kept in the card, not sent.
  case notOnServer
}

extension ModelCatalog {
  /// The LoRAs to offer for a model family: that family's, then those whose family the server
  /// does not know; each group by name. With an unknown model family, every LoRA.
  public func loras(for family: String?) -> [CatalogLoRA] {
    let byName: (CatalogLoRA, CatalogLoRA) -> Bool = {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    guard let family else { return loras.sorted(by: byName) }
    return loras.filter { $0.family == family }.sorted(by: byName)
      + loras.filter { $0.family == nil }.sorted(by: byName)
  }

  public func lora(forFile file: String) -> CatalogLoRA? {
    loras.first { $0.file == file }
  }

  public func status(of selection: LoRASelection, family: String?) -> LoRAStatus {
    guard let lora = lora(forFile: selection.file) else { return .notOnServer }
    if let loraFamily = lora.family, let family, loraFamily != family { return .otherFamily(loraFamily) }
    return .usable
  }
}
