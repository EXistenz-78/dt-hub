import Foundation
import HubKit
import Observation

/// The model chosen in the header, kept across launches. The file is kept even when the
/// server does not have it, so reconnecting to the right server restores it.
@MainActor
@Observable
public final class ModelSelection {
  public private(set) var selectedFile: String?

  @ObservationIgnored private let defaults: UserDefaults
  static let key = "drawThings.selectedModel"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.selectedFile = Self.normalized(defaults.string(forKey: Self.key))
  }

  /// Selects a model file; an empty name clears the selection.
  public func select(_ file: String) {
    selectedFile = Self.normalized(file)
    defaults.set(selectedFile, forKey: Self.key)
  }

  /// The user chose this model in the header: selects it, and, if it is another model than the one selected and
  /// the table knows it (by its file, then by its family), returns `parameters` with the recommended steps,
  /// guidance, sampler and shift. Nil when nothing about the parameters should change. Only the header's menu
  /// goes through here: a preset, the JSON editor, "resume parameters" and the restored session choose models
  /// with `select`, and keep their own values.
  public func choose(
    _ file: String, applyingTo parameters: GenerationParameters, from table: RecommendedSettings, in catalog: ModelCatalog
  ) -> GenerationParameters? {
    let previous = selectedFile
    select(file)
    guard file != previous, let values = table.values(forFile: file, family: catalog.model(forFile: file)?.family) else {
      return nil
    }
    return parameters.applying(values)
  }

  /// An empty name means no model, as it does for RUN (`RunAvailability`).
  private static func normalized(_ file: String?) -> String? {
    guard let file, !file.isEmpty else { return nil }
    return file
  }

  /// The selected model as the catalog describes it; nil if none is selected or installed.
  public func selectedModel(in catalog: ModelCatalog) -> CatalogModel? {
    selectedFile.flatMap(catalog.model(forFile:))
  }
}
