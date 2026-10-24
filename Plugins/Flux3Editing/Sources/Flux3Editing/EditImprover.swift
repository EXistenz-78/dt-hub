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
/// immagini grezze; se non va, o non ci sono le immagini, il flusso standard con lo **stesso** modello e le immagini con i riquadri.
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
    var pupRequest = "", pupAnswer = ""
    if case .pup(let name, let systemPrompt) = mode {
      modelName = name
      let writer = EditPupWriter(ask: { prompt, system, options, images, model in await ask(prompt, system, options, images, model) }, italian: italian)
      let result = await writer.write(document: document, refs: refs, pictures: pupPictures, model: name, systemPrompt: systemPrompt)
      if result.succeeded {
        let note = L.format(.improvedWith, name, L.text(.modePup, italian: italian), italian: italian)
        return EditImproveOutcome(pup: result, standard: nil, note: note, request: result.request, answer: result.answer)
      }
      (pupRequest, pupAnswer) = (result.request, result.answer)
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
    let request = pupRequest.isEmpty ? result.request : pupRequest + "\n\n---\n\n" + result.request
    let answer = pupAnswer.isEmpty ? result.answer : pupAnswer + "\n\n---\n\n" + result.answer
    return EditImproveOutcome(pup: nil, standard: result, note: note, request: request, answer: answer)
  }
}
