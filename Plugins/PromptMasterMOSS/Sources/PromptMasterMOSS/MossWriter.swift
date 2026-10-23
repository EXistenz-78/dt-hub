import DTHubPluginKit
import Foundation

/// Un testo riscritto: l'originale serve a non sovrascrivere ciò che l'utente ha cambiato nel frattempo.
struct MossRewrite: Equatable, Sendable {
  var kind: MossPart.Kind
  var original: String
  var text: String
}

struct MossWriteResult: Sendable {
  var rewrites: [MossRewrite]
  var status: String
  var request: String
  var answer: String
}

/// Il controllo nel codice dell'ordine tassativo (spec §7): le parole tra virgolette non si toccano.
enum MossCheck {
  /// Le parole tra virgolette dritte o ricurve.
  static func quoted(_ text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"|“([^”]+)”") else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { match in
      for group in 1...2 {
        if let r = Range(match.range(at: group), in: text) { return String(text[r]) }
      }
      return nil
    }
  }

  static func preservesQuoted(original: String, rewritten: String) -> Bool { quoted(original).allSatisfy { rewritten.contains($0) } }
}

/// «Scrivi con LLM» (spec §7): una richiesta con tutte le parti, il ripiego per le mancanti, i controlli.
@MainActor
struct MossWriter {
  var ask: (String, String, DTHubLLMOptions) async -> DTHubLLMAnswer
  var italian: Bool = L.systemIsItalian

  static let reminder =
    "IMPORTANT: write the text in English (translate it if it is in another language) and copy every quoted phrase unchanged."

  func write(document: MossDocument, catalog: MossCatalog, system: String, options: DTHubLLMOptions) async -> MossWriteResult {
    let parts = MossBrief.parts(from: document, catalog: catalog)
    guard !parts.isEmpty else {
      return MossWriteResult(rewrites: [], status: L.text(.nothingToWrite, italian: italian), request: "", answer: "")
    }
    let request = MossBrief.message(parts)
    var failureText: String?
    var answer = ""
    var parsed: [MossPart.Kind: String] = [:]
    switch await ask(request, system, options) {
    case .text(let text):
      answer = text
      parsed = MossAnswerParser.parse(text, requested: parts.map(\.kind))
    case .failure(let reason):
      failureText = reason
    }
    var rewrites: [MossRewrite] = []
    var problems: [String] = []
    for part in parts {
      var candidate = parsed[part.kind]
      if candidate == nil || !acceptable(candidate!, for: part) {
        // Ripiego: la sola parte, con l'ordine ripetuto.
        if case .text(let text) = await ask(MossBrief.message([part], reminder: Self.reminder), system, options) {
          answer += "\n\n" + text
          candidate = MossAnswerParser.parse(text, requested: [part.kind])[part.kind]
        } else {
          candidate = nil
        }
      }
      if let candidate, acceptable(candidate, for: part) {
        rewrites.append(MossRewrite(kind: part.kind, original: part.text, text: candidate))
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
    return MossWriteResult(rewrites: rewrites, status: lines.joined(separator: " "), request: request, answer: answer)
  }

  /// Un testo ancora italiano non vale (si riprova); la prosa deve conservare le parole tra virgolette.
  private func acceptable(_ text: String, for part: MossPart) -> Bool {
    if MossLanguage.looksItalian(text) { return false }
    switch part.kind {
    case .summary, .item: return MossCheck.preservesQuoted(original: part.text, rewritten: text)
    case .meta, .tags: return true
    }
  }
}
