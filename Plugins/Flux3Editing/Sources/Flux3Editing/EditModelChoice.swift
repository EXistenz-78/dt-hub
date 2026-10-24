import DTHubPluginKit
import Foundation

/// Come «Migliora prompt» scrive (spec «Migliora prompt» §3).
enum WriteMode: Equatable, Sendable {
  /// Il PUP ufficiale di BFL: il system prompt è l'`i2i_bbox` del suo `system_prompts.json`.
  case pup(name: String, systemPrompt: String)
  /// Qualsiasi altro LLM: il master prompt E e il flusso a parti. `model` è il modello scelto (la richiesta lo nomina, così risponde
  /// proprio lui); nil se l'app non dice quali modelli ha.
  case standard(model: String?)
}

/// Quale modalità usare, dai modelli che l'app dice di avere. Stessa regola dell'app (`LanguageModelRouter`): il primo per nome
/// assegnato alla famiglia, altrimenti il primo su «tutte le altre»; è PUP se la sua cartella ha `system_prompts.json` con `i2i_bbox`.
enum EditModelChoice {
  static let promptsFile = "system_prompts.json"
  static let promptKey = "i2i_bbox"

  /// `readFile` legge il file di un percorso (iniettabile nei test).
  static func mode(family: String?, models: [DTHubLanguageModel], readFile: (String) -> Data?) -> WriteMode {
    func first(_ wanted: String) -> DTHubLanguageModel? {
      models.filter { $0.family == wanted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.first
    }
    let chosen = family.flatMap(first) ?? first("*")
    guard let chosen else { return .standard(model: nil) }
    guard chosen.supportsImages,
      let data = readFile(chosen.path + "/" + promptsFile),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let system = json[promptKey] as? String, !system.isEmpty
    else { return .standard(model: chosen.name) }
    return .pup(name: chosen.name, systemPrompt: system)
  }
}
