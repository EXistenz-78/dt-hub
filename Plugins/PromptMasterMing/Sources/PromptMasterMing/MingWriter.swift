import DTHubPluginKit
import Foundation

/// Un testo riscritto: l'originale serve a non sovrascrivere ciò che l'utente ha cambiato nel frattempo.
struct MingRewrite: Equatable, Sendable {
  var kind: MingPart.Kind
  var original: String
  var text: String
}

struct MingWriteResult: Sendable {
  var rewrites: [MingRewrite]
  var status: String
  var request: String
  var answer: String
}

/// Il risultato di «Componi con LLM»: il JSON letto (nil se non si legge) e lo stato.
struct MingComposeResult: Sendable {
  var imported: MingImported?
  var status: String
  var request: String
  var answer: String
}

/// Il controllo nel codice dell'ordine tassativo: le parole tra virgolette non si toccano.
enum MingCheck {
  static func quoted(_ text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"|“([^”]+)”|«([^»]+)»|‘([^’]+)’") else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { match in
      for group in 1...4 {
        if let r = Range(match.range(at: group), in: text) { return String(text[r]) }
      }
      return nil
    }
  }

  static func preservesQuoted(original: String, rewritten: String) -> Bool { quoted(original).allSatisfy { rewritten.contains($0) } }
}

/// «Scrivi con LLM» (riscrive in inglese stile, luce, descrizioni e relazioni) e «Componi con LLM» (tutto il JSON da un'idea).
@MainActor
struct MingWriter {
  var ask: (String, String, DTHubLLMOptions) async -> DTHubLLMAnswer
  var italian: Bool = L.systemIsItalian

  static let reminder =
    "IMPORTANT: write the text in English (translate it if it is in another language) and copy every quoted phrase unchanged."

  func write(document: MingDocument, catalog: MingCatalog, system: String, options: DTHubLLMOptions) async -> MingWriteResult {
    let parts = MingBrief.parts(from: document, catalog: catalog)
    guard !parts.isEmpty else {
      return MingWriteResult(rewrites: [], status: L.text(.nothingToWrite, italian: italian), request: "", answer: "")
    }
    let request = MingBrief.message(parts)
    var failureText: String?
    var answer = ""
    var parsed: [MingPart.Kind: String] = [:]
    switch await ask(request, system, options) {
    case .text(let text):
      answer = text
      parsed = MingAnswerParser.parse(text, requested: parts.map(\.kind))
    case .failure(let reason):
      failureText = reason
    }
    var rewrites: [MingRewrite] = []
    var problems: [String] = []
    for part in parts {
      var candidate = parsed[part.kind]
      if failureText == nil, candidate == nil || !acceptable(candidate!, for: part) {
        if case .text(let text) = await ask(MingBrief.message([part], reminder: Self.reminder), system, options) {
          answer += "\n\n" + text
          candidate = MingAnswerParser.parse(text, requested: [part.kind])[part.kind]
        } else {
          candidate = nil
        }
      }
      if let candidate, acceptable(candidate, for: part) {
        rewrites.append(MingRewrite(kind: part.kind, original: part.text, text: candidate))
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
    return MingWriteResult(rewrites: rewrites, status: lines.joined(separator: " "), request: request, answer: answer)
  }

  private func acceptable(_ text: String, for part: MingPart) -> Bool {
    if text.filter(\.isLetter).count < 3 { return false }
    if MingLanguage.looksItalian(text) { return false }
    return MingCheck.preservesQuoted(original: part.text, rewritten: text)
  }

  /// Tutto il JSON da un'idea. Una risposta che non si legge si chiede una seconda volta, con l'errore.
  func compose(request: String, system: String, options: DTHubLLMOptions) async -> MingComposeResult {
    var answer = ""
    var reason = ""
    for attempt in 0..<2 {
      let message = attempt == 0 ? request : request + "\n\nYour previous answer could not be read (\(reason)). Reply with ONE valid JSON object only."
      switch await ask(message, system, options) {
      case .failure(let failure):
        return MingComposeResult(imported: nil, status: failure, request: request, answer: answer)
      case .text(let text):
        answer += (answer.isEmpty ? "" : "\n\n") + text
        switch MingImporter.parse(MingAnswerParser.clean(text)) {
        case .success(let imported) where !imported.layers.isEmpty:
          return MingComposeResult(
            imported: imported, status: L.format(.composedCount, imported.layers.count, italian: italian), request: request,
            answer: answer)
        case .success: reason = "no layers"
        case .failure(let failure): reason = failure.reason
        }
      }
    }
    return MingComposeResult(imported: nil, status: L.format(.composeFailed, reason, italian: italian), request: request, answer: answer)
  }
}
