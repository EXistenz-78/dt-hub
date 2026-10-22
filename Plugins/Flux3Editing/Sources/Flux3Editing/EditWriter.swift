import DTHubPluginKit
import Foundation

/// Un testo riscritto: l'originale serve a non sovrascrivere ciò che l'utente ha cambiato nel frattempo.
struct EditRewrite: Equatable, Sendable {
  var kind: EditPart.Kind
  var original: String
  var text: String
}

struct EditWriteResult: Sendable {
  var rewrites: [EditRewrite]
  var status: String
  var request: String
  var answer: String
}

/// «Scrivi con LLM» (spec §7): una richiesta con tutte le parti, il ripiego per le mancanti, il controllo dei segnaposto.
@MainActor
struct EditWriter {
  var ask: (String, String, DTHubLLMOptions) async -> DTHubLLMAnswer
  var italian: Bool = L.systemIsItalian

  static let reminder =
    "IMPORTANT: write the text in English (translate it if it is in another language). Copy every <placeholder> exactly as written, the same number of times, and every quoted phrase unchanged."

  /// `allowedTags`: i segnaposto che la prosa può citare (gli id degli elementi e `ref_image_N` delle immagini che ci sono).
  func write(document: EditDocument, allowedTags: Set<String>, system: String, options: DTHubLLMOptions) async -> EditWriteResult {
    let parts = EditBrief.parts(from: document)
    guard !parts.isEmpty else {
      return EditWriteResult(rewrites: [], status: L.text(.nothingToWrite, italian: italian), request: "", answer: "")
    }
    let request = EditBrief.message(parts)
    var failureText: String?
    var answer = ""
    var parsed: [EditPart.Kind: String] = [:]
    switch await ask(request, system, options) {
    case .text(let text):
      answer = text
      parsed = EditAnswerParser.parse(text, requested: parts.map(\.kind))
    case .failure(let reason):
      failureText = reason
    }
    var rewrites: [EditRewrite] = []
    var problems: [String] = []
    for part in parts {
      var candidate = parsed[part.kind]
      if candidate == nil || !acceptable(candidate!, for: part, allowed: allowedTags) {
        // Ripiego: la sola parte, con l'ordine ripetuto.
        if case .text(let text) = await ask(EditBrief.message([part], reminder: Self.reminder), system, options) {
          answer += "\n\n" + text
          candidate = EditAnswerParser.parse(text, requested: [part.kind])[part.kind]
        } else {
          candidate = nil
        }
      }
      if let candidate, acceptable(candidate, for: part, allowed: allowedTags) {
        rewrites.append(EditRewrite(kind: part.kind, original: part.text, text: candidate))
      } else if let candidate, !tagsRespected(candidate, for: part, allowed: allowedTags) {
        problems.append(part.kind.title + " (" + L.text(.tagsChanged, italian: italian) + ")")
      } else {
        problems.append(part.kind.title)
      }
    }
    var lines: [String] = []
    if let failureText, rewrites.isEmpty { lines.append(failureText) }
    if !rewrites.isEmpty { lines.append(L.format(.writtenCount, rewrites.count, italian: italian)) }
    if !problems.isEmpty && !(failureText != nil && rewrites.isEmpty) {
      lines.append(L.format(.failedParts, problems.joined(separator: ", "), italian: italian))
    }
    return EditWriteResult(rewrites: rewrites, status: lines.joined(separator: " "), request: request, answer: answer)
  }

  private func acceptable(_ text: String, for part: EditPart, allowed: Set<String>) -> Bool {
    // Un testo che doveva diventare inglese e resta italiano non vale: si riprova.
    if EditLanguage.looksItalian(text) { return false }
    return EditTags.quoted(part.text).allSatisfy { text.contains($0) } && tagsRespected(text, for: part, allowed: allowed)
  }

  /// La prosa tiene ogni segnaposto che aveva, lo stesso numero di volte almeno, e può aggiungerne solo tra quelli permessi;
  /// la descrizione di un elemento tiene esattamente i suoi.
  private func tagsRespected(_ text: String, for part: EditPart, allowed: Set<String>) -> Bool {
    let original = EditTags.tags(in: part.text), rewritten = EditTags.tags(in: text)
    switch part.kind {
    case .element:
      return original.sorted() == rewritten.sorted()
    case .prose:
      let counts = Dictionary(rewritten.map { ($0, 1) }, uniquingKeysWith: +)
      let originalCounts = Dictionary(original.map { ($0, 1) }, uniquingKeysWith: +)
      guard originalCounts.allSatisfy({ (counts[$0.key] ?? 0) >= $0.value }) else { return false }
      return Set(rewritten).isSubset(of: allowed.union(original))
    }
  }
}
