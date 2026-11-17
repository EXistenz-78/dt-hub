import Foundation
import HubKit

/// Adds, removes and replaces the LoRAs of the parameters and, for the Turbo ones of the catalog, applies their steps,
/// guidance and shift and puts the old values back. A LoRA that arrives in bulk (preset, project, recall) never goes
/// through here, so every method first forgets the activations of LoRAs that are no longer chosen.
public struct LoRAActivator: Equatable, Sendable {
  public private(set) var turbo = TurboLoRAs()

  public init() {}

  /// Adds the LoRA; one already chosen only gets its weight, mode and trigger updated (not an activation).
  public mutating func add(_ lora: LoRASelection, to parameters: inout GenerationParameters, catalog: ModelCatalog) {
    prune(parameters)
    if parameters.loras.contains(where: { $0.file == lora.file }) {
      parameters.updateLoRA(lora)
      return
    }
    parameters.loras.append(lora)
    activate(lora.file, in: &parameters, catalog: catalog)
  }

  public mutating func remove(_ file: String, from parameters: inout GenerationParameters) {
    prune(parameters)
    turbo.deactivate(file: file, in: &parameters)
    parameters.removeLoRA(file)
  }

  /// Same rules as `GenerationParameters.replaceLoRA`: nothing when `old` is missing or the new file is already chosen.
  public mutating func replace(
    _ old: String, with lora: LoRASelection, in parameters: inout GenerationParameters, catalog: ModelCatalog
  ) {
    prune(parameters)
    guard lora.file != old, parameters.loras.contains(where: { $0.file == old }),
      !parameters.loras.contains(where: { $0.file == lora.file })
    else { return }
    turbo.deactivate(file: old, in: &parameters)
    parameters.replaceLoRA(old, with: lora.file, weight: lora.weight, trigger: lora.trigger)
    activate(lora.file, in: &parameters, catalog: catalog)
  }

  private mutating func prune(_ parameters: GenerationParameters) {
    turbo.prune(keeping: Set(parameters.loras.map(\.file)))
  }

  private mutating func activate(_ file: String, in parameters: inout GenerationParameters, catalog: ModelCatalog) {
    guard let entry = catalog.loras.first(where: { $0.file == file }), entry.category == "turbo" else { return }
    let values = TurboValues(steps: entry.steps, guidance: entry.guidance, shift: entry.shift)
    turbo.activate(file: file, values: values, in: &parameters)
  }
}
