import DTHubPluginKit
import Foundation

struct EditImproveOutcome: Sendable {
  /// Il risultato in modalità PUP, se è riuscito.
  var pup: EditPupResult?
  /// Il risultato in modalità standard (anche come ripiego del PUP).
  var standard: EditWriteResult?
  /// «Migliorato con <modello> (modalità PUP)»: vuota se non si è scritto niente.
  var note: String
  /// Richiesta e risposta, per i file di lavoro.
  var request: String
  var answer: String
}

/// «Migliora prompt» (spec «Migliora prompt» §3–§5): sceglie il flusso dalla modalità. PUP: una richiesta nel suo formato con le
/// immagini grezze; se non va si dice perché e i testi restano (il PUP risponde nel suo formato qualunque system prompt: niente
/// ripiego standard con lui). Standard: il master E, a parti, con le immagini coi riquadri.
@MainActor
struct EditImprover {
  /// prompt, system prompt, opzioni, immagini, nome del modello (nil: quello che sceglie l'app).
  var ask: (String, String, DTHubLLMOptions, [String], String?) async -> DTHubLLMAnswer
  var italian: Bool = L.systemIsItalian

  func improve(
    document: EditDocument, refs: [RefImage], allowedTags: Set<String>, mode: WriteMode, pupPictures: [EditPicture],
    drawnPictures: [EditPicture], standardSystem: String
  ) async -> EditImproveOutcome {
    var modelName: String?
    if case .standard(let model) = mode { modelName = model }
    if case .pup(let name, let systemPrompt) = mode {
      modelName = name
      // Il PUP risponde nel suo formato qualunque system prompt gli si dia: con lui non c'è un ripiego standard. Si dice perché non
      // è andata e i testi restano.
      func stop(_ status: String, _ request: String = "", _ answer: String = "") -> EditImproveOutcome {
        EditImproveOutcome(
          pup: nil, standard: EditWriteResult(rewrites: [], status: status, request: request, answer: answer), note: "", request: request,
          answer: answer)
      }
      guard !pupPictures.isEmpty else { return stop(L.format(.pupNoPictures, name, italian: italian)) }
      let writer = EditPupWriter(ask: { prompt, system, options, images, model in await ask(prompt, system, options, images, model) }, italian: italian)
      let result = await writer.write(document: document, refs: refs, pictures: pupPictures, model: name, systemPrompt: systemPrompt)
      if result.succeeded {
        let note = L.format(.improvedWith, name, L.text(.modePup, italian: italian), italian: italian)
        return EditImproveOutcome(pup: result, standard: nil, note: note, request: result.request, answer: result.answer)
      }
      if !result.status.isEmpty { return stop(L.format(.pupFailedWith, name, result.status, italian: italian), result.request, result.answer) }
      return stop(L.format(.pupUnusable, name, italian: italian), result.request, result.answer)
    }
    let model = modelName
    let writer = EditWriter(ask: { prompt, system, options, images in await ask(prompt, system, options, images, model) }, italian: italian)
    let result = await writer.write(
      document: document, refs: refs, allowedTags: allowedTags, pictures: drawnPictures, system: standardSystem, options: EditPrompts.options)
    var note = ""
    if !result.rewrites.isEmpty {
      let standard = L.text(.modeStandard, italian: italian)
      note = modelName.map { L.format(.improvedWith, $0, standard, italian: italian) } ?? L.format(.improvedStandard, standard, italian: italian)
    }
    return EditImproveOutcome(pup: nil, standard: result, note: note, request: result.request, answer: result.answer)
  }
}
