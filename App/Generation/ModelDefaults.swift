import Foundation
import HubCore
import HubKit
import Observation

/// The recommended values per model, in layers: the file the app ships (`RecommendedSettings.json`), with what the
/// list Draw Things publishes knows of newer models once `refresh()` has it, and on top the user's own defaults
/// (`recommended-overrides.json`), which always win. Apart from the Generation tab, which only asks and applies.
@MainActor
@Observable
final class ModelDefaults {
  @ObservationIgnored private var base: RecommendedSettings = {
    guard let url = Bundle.main.url(forResource: "RecommendedSettings", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return .empty }
    return RecommendedSettings(data: data)
  }()

  @ObservationIgnored private let store = RecommendedOverridesStore(fileURL: RecommendedOverridesStore.defaultFileURL)
  /// The defaults the user saved per model; read from disk at launch.
  private(set) var saved: RecommendedSettings = RecommendedOverridesStore(
    fileURL: RecommendedOverridesStore.defaultFileURL
  ).load()
  /// A line under the Sampling card about the last save, reset or model change (a missing LoRA); nil when none.
  var notice: String?

  var recommended: RecommendedSettings { base.overriding(with: saved) }

  /// The list of official configurations Draw Things publishes, downloaded once per launch and kept on disk.
  private static let liveConfigurations = CachedDownload(
    address: URL(string: "https://models.drawthings.ai/configs.json")!, cacheURL: CachedDownload.supportFile("configs-list.json"),
    isValid: { RecommendedSettings(configurations: $0) != .empty })

  /// Adds to the table the models released after this app was built (at launch; offline, the copy saved last time).
  func refresh() async {
    guard let data = await Self.liveConfigurations.data() else { return }
    base = base.merging(RecommendedSettings(configurations: data))
  }

  /// The LoRAs of the model's saved default that the server does not have: they are left out, and the line says which.
  func reportMissingLoRAs(forFile file: String, in catalog: ModelCatalog) {
    guard catalog.fileCount > 0,
      let values = recommended.values(forFile: file, family: catalog.model(forFile: file)?.family)
    else { return }
    let missing = values.missingLoRAs(installed: Set(catalog.loras.map(\.file)))
    if !missing.isEmpty {
      notice = missing.map { String(format: String(localized: "defaults.loraMissing"), $0) }.joined(separator: "\n")
    }
  }

  /// True when the user saved a default for the model.
  func hasSaved(forFile file: String) -> Bool { saved.hasModel(forFile: file) }

  /// Keeps the steps, guidance, sampler, shift and LoRAs of `parameters` as the model's default.
  func save(_ parameters: GenerationParameters, forFile file: String) {
    saved = saved.setting(RecommendedValues(capturing: parameters), forFile: file)
    store.save(saved)
    notice = String(localized: "defaults.saved")
  }

  /// Forgets the model's saved default; the answer is `parameters` with the values that remain (the app's, the list's
  /// or its family's), if there are any.
  func reset(forFile file: String, in catalog: ModelCatalog, parameters: GenerationParameters) -> GenerationParameters {
    saved = saved.removingModel(forFile: file)
    store.save(saved)
    notice = String(localized: "defaults.resetDone")
    guard let values = recommended.values(forFile: file, family: catalog.model(forFile: file)?.family) else { return parameters }
    let installed: Set<String>? = catalog.fileCount == 0 ? nil : Set(catalog.loras.map(\.file))
    return parameters.applying(values, installedLoRAs: installed)
  }
}
