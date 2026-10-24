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

/// «Migliora prompt» (spec §7): una richiesta con tutte le parti, il ripiego per le mancanti, il controllo dei segnaposto.
@MainActor
struct EditWriter {
  var ask: (String, String, DTHubLLMOptions, [String]) async -> DTHubLLMAnswer
  var italian: Bool = L.systemIsItalian

  static let reminder =
    "IMPORTANT: write the text in English (translate it if it is in another language). Copy every <placeholder> exactly as written, the same number of times, and every quoted phrase unchanged."

  /// `allowedTags`: i segnaposto che la prosa può citare (gli id degli elementi e `ref_image_N` delle immagini che ci sono).
  func write(
    document: EditDocument, refs: [RefImage], allowedTags: Set<String>, pictures: [EditPicture] = [], system: String,
    options: DTHubLLMOptions
  ) async -> EditWriteResult {
    let parts = EditBrief.parts(from: document)
    guard !parts.isEmpty else {
      return EditWriteResult(rewrites: [], status: L.text(.nothingToWrite, italian: italian), request: "", answer: "")
    }
    // All the pictures go along, with every part and with every retry: they are what lets the model see the scene as a whole.
    var picturesDropped = false
    var sent = pictures
    var request = EditBrief.message(parts, context: EditBrief.context(for: parts, in: document, refs: refs, pictures: sent), pictures: sent)
    var failureText: String?
    var answer = ""
    var parsed: [EditPart.Kind: String] = [:]
    var first = await ask(request, system, options, sent.map(\.path))
    if case .failure = first, !sent.isEmpty {
      // The model cannot take pictures (or failed with them): once more with the texts only.
      picturesDropped = true
      sent = []
      request = EditBrief.message(parts, context: EditBrief.context(for: parts, in: document, refs: refs))
      first = await ask(request, system, options, [])
    }
    switch first {
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
        let own = picturesDropped ? [] : pictures
        let message = EditBrief.message(
          [part], context: EditBrief.context(for: [part], in: document, refs: refs, pictures: own), pictures: own, reminder: Self.reminder)
        if case .text(let text) = await ask(message, system, options, own.map(\.path)) {
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
    if picturesDropped { lines.append(L.text(.imagesNotSent, italian: italian)) }
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
