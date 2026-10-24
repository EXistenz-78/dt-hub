import DTHubPluginKit
import Foundation

/// Come «Scrivi con LLM» scrive (come in Flux3 Editing: spec «Migliora prompt» §3).
enum F3WriteMode: Equatable, Sendable {
  /// Il PUP ufficiale di BFL: il system prompt è il `t2i_bbox` del suo `system_prompts.json`.
  case pup(name: String, systemPrompt: String)
  /// Qualsiasi altro LLM: il master prompt del plug-in. `model` è il modello scelto (la richiesta lo nomina); nil se l'app non dice
  /// quali modelli ha.
  case standard(model: String?)
}

enum F3ModelChoice {
  static let promptsFile = "system_prompts.json"
  static let promptKey = "t2i_bbox"

  /// Stessa regola dell'app: il primo per nome assegnato alla famiglia, altrimenti il primo su «tutte le altre»; è PUP se la sua
  /// cartella ha `system_prompts.json` con `t2i_bbox` (basta il file: `t2i_bbox` è solo testo). Un modello assegnato solo a «describe» non
  /// scrive prompt, quindi non è un candidato.
  static func mode(family: String?, models: [DTHubLanguageModel], readFile: (String) -> Data?) -> F3WriteMode {
    func first(_ wanted: String) -> DTHubLanguageModel? {
      models.filter { $0.family == wanted && $0.use != "describe" }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.first
    }
    guard let chosen = family.flatMap(first) ?? first("*") else { return .standard(model: nil) }
    guard let data = readFile(chosen.path + "/" + promptsFile),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let system = json[promptKey] as? String, !system.isEmpty
    else { return .standard(model: chosen.name) }
    return .pup(name: chosen.name, systemPrompt: system)
  }
}
