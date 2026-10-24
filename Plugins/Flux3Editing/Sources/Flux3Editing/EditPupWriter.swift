import DTHubPluginKit
import Foundation

/// Il risultato di «Migliora prompt» in modalità PUP.
struct EditPupResult: Sendable {
  /// Il paragrafo, che diventa la prosa.
  var prose: String?
  /// La `desc` di ogni nostro elemento, per id.
  var descriptions: [String: String]
  /// Le righe che il modello ha aggiunto.
  var extraRows: [PupRow]
  var status: String
  var request: String
  var answer: String
  var succeeded: Bool

  static func failed(status: String = "", request: String = "", answer: String = "") -> EditPupResult {
    EditPupResult(prose: nil, descriptions: [:], extraRows: [], status: status, request: request, answer: answer, succeeded: false)
  }
}

/// «Migliora prompt» col PUP ufficiale: una richiesta nel suo formato nativo (spec «Migliora prompt» §4), la riconciliazione con i
/// nostri riquadri, i controlli sul testo intero e un solo nuovo tentativo.
@MainActor
struct EditPupWriter {
  /// prompt, system prompt, opzioni, immagini, nome del modello.
  var ask: (String, String, DTHubLLMOptions, [String], String) async -> DTHubLLMAnswer
  var italian: Bool = L.systemIsItalian

  func write(document: EditDocument, refs: [RefImage], pictures: [EditPicture], model: String, systemPrompt: String) async -> EditPupResult {
    let locked = EditComposer.lockedRows(document, refs: refs)
    guard !locked.isEmpty, !pictures.isEmpty else { return .failed() }
    var request = "", answer = ""
    for attempt in 0..<2 {
      request = PupRequest.message(prose: document.prose, locked: locked, reminder: attempt == 0 ? nil : EditWriter.reminder)
      switch await ask(request, systemPrompt, PupRequest.options, pictures.map(\.path), model) {
      case .failure(let reason):
        return .failed(status: reason, request: request, answer: answer)
      case .text(let text):
        answer += (answer.isEmpty ? "" : "\n\n") + text
        let reconciled = PupReconcile.reconcile(text, locked: locked)
        if acceptable(reconciled, locked: locked, document: document) {
          let descriptions = Dictionary(reconciled.rows.map { ($0.id, $0.desc) }, uniquingKeysWith: { first, _ in first })
          return EditPupResult(
            prose: reconciled.caption, descriptions: descriptions, extraRows: reconciled.added, status: "", request: request,
            answer: answer, succeeded: true)
        }
      }
    }
    return .failed(request: request, answer: answer)
  }

  /// Ogni nostro id citato come `<id>`, le parole tra virgolette di ingresso ancora presenti, e niente italiano.
  private func acceptable(_ result: PupReconciled, locked: [PupRow], document: EditDocument) -> Bool {
    let caption = result.caption
    guard !caption.isEmpty, locked.allSatisfy({ caption.contains("<\($0.id)>") }) else { return false }
    let output = ([caption] + result.rows.map(\.desc) + result.added.map(\.desc)).joined(separator: "\n")
    let input = ([document.prose] + document.elements.map(\.desc))
    guard input.flatMap(EditTags.quoted).allSatisfy({ output.contains($0) }) else { return false }
    return !EditLanguage.looksItalian(caption) && !result.rows.contains { EditLanguage.looksItalian($0.desc) }
  }
}
