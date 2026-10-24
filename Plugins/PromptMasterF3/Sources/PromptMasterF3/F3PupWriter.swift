import DTHubPluginKit
import Foundation

/// Il risultato di «Scrivi con LLM» in modalità PUP.
struct F3PupResult: Sendable {
  /// Il paragrafo: diventa la composizione (descrizione e voci vi sono già dentro).
  var caption: String?
  /// La `desc` di ogni nostro elemento, per id.
  var descriptions: [String: String]
  /// Le righe che il modello ha aggiunto: diventano elementi.
  var addedRows: [PupRow]
  var status: String
  var request: String
  var answer: String
  var succeeded: Bool

  static func failed(status: String = "", request: String = "", answer: String = "") -> F3PupResult {
    F3PupResult(caption: nil, descriptions: [:], addedRows: [], status: status, request: request, answer: answer, succeeded: false)
  }
}

/// «Scrivi con LLM» col PUP ufficiale: una richiesta nel suo formato `t2i_bbox`, la riconciliazione con i nostri riquadri, i controlli sul
/// testo intero e un solo nuovo tentativo.
@MainActor
struct F3PupWriter {
  /// prompt, system prompt, opzioni, nome del modello.
  var ask: (String, String, DTHubLLMOptions, String) async -> DTHubLLMAnswer
  var italian: Bool = L.systemIsItalian

  func write(document: F3Document, terms: [String], model: String, systemPrompt: String) async -> F3PupResult {
    let locked = document.elements.map { PupRow(id: $0.id, bbox: [$0.box.y0, $0.box.x0, $0.box.y1, $0.box.x1], desc: $0.desc) }
    guard !locked.isEmpty else { return .failed() }
    let prose = F3Composer.prose(description: document.description, terms: terms, composition: document.composition)
    var request = "", answer = ""
    for attempt in 0..<2 {
      request = F3PupRequest.message(prose: prose, locked: locked, reminder: attempt == 0 ? nil : F3Writer.idReminder)
      switch await ask(request, systemPrompt, F3PupRequest.options, model) {
      case .failure(let reason):
        return .failed(status: reason, request: request, answer: answer)
      case .text(let text):
        answer += (answer.isEmpty ? "" : "\n\n") + text
        let reconciled = PupReconcile.reconcile(text, locked: locked)
        if acceptable(reconciled, locked: locked, document: document, prose: prose) {
          let descriptions = Dictionary(reconciled.rows.map { ($0.id, $0.desc) }, uniquingKeysWith: { first, _ in first })
          return F3PupResult(
            caption: reconciled.caption, descriptions: descriptions, addedRows: reconciled.added, status: "", request: request,
            answer: answer, succeeded: true)
        }
      }
    }
    return .failed(request: request, answer: answer)
  }

  /// Una tabella in fondo, ogni nostro id citato come `<id>`, nessun segnaposto fuori dai nostri e dalle righe aggiunte valide, le parole
  /// tra virgolette di ingresso ancora presenti, e niente italiano.
  private func acceptable(_ result: PupReconciled, locked: [PupRow], document: F3Document, prose: String) -> Bool {
    let caption = result.caption
    guard result.hadList, !caption.isEmpty, locked.allSatisfy({ caption.contains("<\($0.id)>") }) else { return false }
    let allowed = Set(locked.map(\.id) + result.added.map(\.id))
    guard F3IDParser.ids(in: caption).allSatisfy({ allowed.contains($0.id) }) else { return false }
    let output = ([caption] + result.rows.map(\.desc) + result.added.map(\.desc)).joined(separator: "\n")
    let input = [prose] + document.elements.map(\.desc)
    guard input.flatMap(F3IDCheck.quoted).allSatisfy({ output.contains($0) }) else { return false }
    return !F3Language.looksItalian(caption) && !result.rows.contains { F3Language.looksItalian($0.desc) }
  }
}
