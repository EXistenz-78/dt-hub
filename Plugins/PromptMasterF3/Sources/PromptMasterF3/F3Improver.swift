import DTHubPluginKit
import Foundation

struct F3ImproveOutcome: Sendable {
  var pup: F3PupResult?
  var standard: F3WriteResult?
  /// «Migliorato con <modello> (modalità PUP)»: vuota se non si è scritto niente.
  var note: String
  var request: String
  var answer: String
}

/// «Scrivi con LLM» (come «Migliora prompt» di Flux3 Editing): sceglie il flusso dalla modalità. PUP: una richiesta `t2i_bbox`; se non
/// va si dice perché e i testi restano (il PUP risponde nel suo formato qualunque system prompt: niente ripiego standard con lui).
/// Standard: il master prompt del plug-in, a parti, col modello scelto.
@MainActor
struct F3Improver {
  /// prompt, system prompt, opzioni, nome del modello (nil: quello che sceglie l'app).
  var ask: (String, String, DTHubLLMOptions, String?) async -> DTHubLLMAnswer
  var italian: Bool = L.systemIsItalian

  func improve(
    document: F3Document, catalog: F3Catalog, mode: F3WriteMode, standardSystem: String, standardOptions: DTHubLLMOptions
  ) async -> F3ImproveOutcome {
    var modelName: String?
    switch mode {
    case .pup(let name, let systemPrompt):
      func stop(_ status: String, _ request: String = "", _ answer: String = "") -> F3ImproveOutcome {
        F3ImproveOutcome(
          pup: nil, standard: F3WriteResult(rewrites: [], status: status, request: request, answer: answer), note: "", request: request,
          answer: answer)
      }
      let writer = F3PupWriter(ask: { prompt, system, options, model in await ask(prompt, system, options, model) }, italian: italian)
      let terms = catalog.termNames(document.selection, mode: document.mode)
      let result = await writer.write(document: document, terms: terms, model: name, systemPrompt: systemPrompt)
      if result.succeeded {
        let note = L.format(.improvedWith, name, L.text(.modePup, italian: italian), italian: italian)
        return F3ImproveOutcome(pup: result, standard: nil, note: note, request: result.request, answer: result.answer)
      }
      if !result.status.isEmpty { return stop(L.format(.pupFailedWith, name, result.status, italian: italian), result.request, result.answer) }
      return stop(L.format(.pupUnusable, name, italian: italian), result.request, result.answer)
    case .standard(let model):
      modelName = model
    }
    let model = modelName
    let writer = F3Writer(ask: { prompt, system, options in await ask(prompt, system, options, model) }, italian: italian)
    let result = await writer.write(document: document, catalog: catalog, system: standardSystem, options: standardOptions)
    var note = ""
    if !result.rewrites.isEmpty {
      let standard = L.text(.modeStandard, italian: italian)
      note = model.map { L.format(.improvedWith, $0, standard, italian: italian) } ?? L.format(.improvedStandard, standard, italian: italian)
    }
    return F3ImproveOutcome(pup: nil, standard: result, note: note, request: result.request, answer: result.answer)
  }
}
